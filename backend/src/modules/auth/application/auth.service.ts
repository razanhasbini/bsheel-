import { BadRequestException, ForbiddenException, Injectable, UnauthorizedException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import { hash, verify } from 'argon2';
import { randomBytes, randomUUID } from 'node:crypto';
import type { Request } from 'express';
import type { AccessTokenPayload, AuthUser, RefreshTokenPayload } from '../../../common/auth/auth-user.js';
import type { Environment } from '../../../config/environment.js';
import type { RegistrationPendingConfirmation, TokenPair } from '../domain/auth.types.js';
import { AuthRepository } from '../infrastructure/auth.repository.js';
import { AuthActionTokenCipher } from '../infrastructure/auth-action-token-cipher.js';
import { OAuthIdentityVerifier } from '../infrastructure/oauth-identity-verifier.js';
import type { LoginDto, OAuthSignInDto, RegisterDto } from '../presentation/auth.dto.js';
import { assertPasswordPolicy } from '../domain/password-policy.js';

@Injectable()
export class AuthService {
  constructor(
    private readonly repository: AuthRepository,
    private readonly jwt: JwtService,
    private readonly config: ConfigService<Environment, true>,
    private readonly oauthVerifier: OAuthIdentityVerifier,
    private readonly actionTokenCipher: AuthActionTokenCipher,
  ) {}

  async register(input: RegisterDto, request: Request): Promise<TokenPair | RegistrationPendingConfirmation> {
    if (!input.ageVerified) {
      throw new ForbiddenException({ code: 'AGE_VERIFICATION_REQUIRED', message: 'You must confirm that you are at least 13 years old' });
    }
    assertPasswordPolicy(input.password, input.username, input.email);
    const confirmationRequired = this.config.get('AUTH_EMAIL_CONFIRMATION_REQUIRED', { infer: true });
    const confirmationToken = confirmationRequired
      ? this.actionTokenCipher.protect(randomBytes(32).toString('base64url'))
      : undefined;
    const account = await this.repository.createPasswordAccount({
      ...input,
      passwordHash: await hash(input.password, { type: 2 }),
      confirmation: confirmationToken ? {
        tokenHash: confirmationToken.hash,
        encryptedToken: confirmationToken.encrypted,
        expiresAt: new Date(Date.now() + 24 * 60 * 60 * 1000),
      } : undefined,
    });
    if (confirmationRequired) return { confirmationRequired: true };
    return this.issueTokenPair(account, request);
  }

  async login(input: LoginDto, request: Request): Promise<TokenPair> {
    const account = await this.repository.findAccountByEmail(input.email);
    const valid = account?.passwordHash ? await verify(account.passwordHash, input.password) : false;
    if (!account || !valid) {
      throw new UnauthorizedException({ code: 'INVALID_CREDENTIALS', message: 'Invalid email or password' });
    }
    if (!account.emailVerified) {
      throw new ForbiddenException({
        code: 'EMAIL_NOT_CONFIRMED',
        message: 'Please confirm your email before logging in',
      });
    }
    if (account.status !== 'active') {
      throw new ForbiddenException({ code: 'ACCOUNT_RESTRICTED', message: `This account is ${account.status}` });
    }
    await this.repository.touchLastLogin(account.id);
    return this.issueTokenPair(account, request);
  }

  async oauth(input: OAuthSignInDto, request: Request): Promise<TokenPair> {
    const identity = await this.oauthVerifier.verify(
      input.provider,
      input.idToken,
      input.nonce,
      input.displayName,
    );
    const account = await this.repository.findOrCreateOAuthAccount(identity, input.ageVerified);
    if (account.status !== 'active') {
      throw new ForbiddenException({ code: 'ACCOUNT_RESTRICTED', message: `This account is ${account.status}` });
    }
    await this.repository.touchLastLogin(account.id);
    return this.issueTokenPair(account, request);
  }

  async updatePassword(userId: string, newPassword: string) {
    const identity = await this.repository.passwordIdentity(userId);
    if (!identity) throw new UnauthorizedException();
    assertPasswordPolicy(newPassword, identity.username, identity.email);
    const account = await this.repository.updatePassword(userId, await hash(newPassword, { type: 2 }));
    return { id: account.id, email: account.email };
  }

  async requestPasswordRecovery(email: string): Promise<void> {
    const token = randomBytes(32).toString('base64url');
    const protectedToken = this.actionTokenCipher.protect(token);
    await this.repository.requestPasswordRecovery({
      email,
      tokenHash: protectedToken.hash,
      encryptedToken: protectedToken.encrypted,
      expiresAt: new Date(Date.now() + 60 * 60 * 1000),
    });
  }

  async completePasswordRecovery(token: string, newPassword: string): Promise<void> {
    const tokenHash = this.actionTokenCipher.hash(token);
    const identity = await this.repository.recoveryIdentity(tokenHash);
    if (!identity) {
      throw this.invalidRecoveryToken();
    }
    assertPasswordPolicy(newPassword, identity.username, identity.email);
    const completed = await this.repository.completePasswordRecovery(
      identity.tokenId,
      tokenHash,
      await hash(newPassword, { type: 2 }),
    );
    if (!completed) throw this.invalidRecoveryToken();
  }

  async requestEmailConfirmation(email: string): Promise<void> {
    const token = randomBytes(32).toString('base64url');
    const protectedToken = this.actionTokenCipher.protect(token);
    await this.repository.requestEmailConfirmation({
      email,
      tokenHash: protectedToken.hash,
      encryptedToken: protectedToken.encrypted,
      expiresAt: new Date(Date.now() + 24 * 60 * 60 * 1000),
    });
  }

  async completeEmailConfirmation(token: string): Promise<void> {
    const completed = await this.repository.completeEmailConfirmation(
      this.actionTokenCipher.hash(token),
    );
    if (!completed) {
      throw new BadRequestException({
        code: 'INVALID_CONFIRMATION_TOKEN',
        message: 'The email confirmation link is invalid or expired',
      });
    }
  }

  async refresh(rawToken: string, request: Request): Promise<TokenPair> {
    let payload: RefreshTokenPayload;
    try {
      payload = await this.jwt.verifyAsync<RefreshTokenPayload>(rawToken, {
        secret: this.config.get('JWT_REFRESH_SECRET', { infer: true }),
      });
      if (payload.type !== 'refresh') throw new Error('Wrong token type');
    } catch {
      throw new UnauthorizedException({ code: 'INVALID_REFRESH_TOKEN', message: 'Refresh token is invalid or expired' });
    }

    return this.repository.transaction(async (transaction) => {
      const session = await this.repository.findSessionForUpdate(payload.sid, transaction);
      if (!session || session.revokedAt || session.expiresAt <= new Date()) {
        throw new UnauthorizedException({ code: 'INVALID_REFRESH_SESSION', message: 'Refresh session is no longer valid' });
      }
      if (session.rotatedAt) {
        await this.repository.revokeFamily(session.familyId, transaction);
        throw new UnauthorizedException({ code: 'REFRESH_TOKEN_REUSED', message: 'Refresh token reuse was detected; sign in again' });
      }
      if (!(await verify(session.tokenHash, rawToken)) || session.tokenVersion !== payload.tokenVersion) {
        await this.repository.revokeFamily(session.familyId, transaction);
        throw new UnauthorizedException({ code: 'INVALID_REFRESH_TOKEN', message: 'Refresh token is invalid' });
      }
      const account = await this.repository.findActiveAccountById(session.userId);
      if (!account || account.tokenVersion !== payload.tokenVersion) {
        await this.repository.revokeFamily(session.familyId, transaction);
        throw new UnauthorizedException({ code: 'SESSION_REVOKED', message: 'Session has been revoked' });
      }
      await this.repository.markSessionRotated(session.id, transaction);
      return this.issueTokenPair(account, request, session.familyId, transaction);
    });
  }

  async logout(rawToken?: string): Promise<void> {
    if (!rawToken) return;
    try {
      const payload = await this.jwt.verifyAsync<RefreshTokenPayload>(rawToken, {
        secret: this.config.get('JWT_REFRESH_SECRET', { infer: true }),
        ignoreExpiration: true,
      });
      await this.repository.revokeSession(payload.sid);
    } catch {
      // Logout is deliberately idempotent and does not reveal token validity.
    }
  }

  private invalidRecoveryToken(): BadRequestException {
    return new BadRequestException({
      code: 'INVALID_RECOVERY_TOKEN',
      message: 'The password recovery link is invalid or expired',
    });
  }

  private async issueTokenPair(
    account: AuthUser & { tokenVersion: number },
    request: Request,
    familyId: string = randomUUID(),
    transaction?: Parameters<AuthRepository['createSession']>[1],
  ): Promise<TokenPair> {
    const sessionId = randomUUID();
    const refreshTtl = this.config.get('JWT_REFRESH_TTL_SECONDS', { infer: true });
    const accessTtl = this.config.get('JWT_ACCESS_TTL_SECONDS', { infer: true });
    const accessPayload: AccessTokenPayload = {
      sub: account.id,
      email: account.email,
      role: account.role,
      tokenVersion: account.tokenVersion,
      type: 'access',
    };
    const refreshPayload: RefreshTokenPayload = {
      sub: account.id,
      sid: sessionId,
      familyId,
      jti: randomUUID(),
      tokenVersion: account.tokenVersion,
      type: 'refresh',
    };
    const [accessToken, refreshToken] = await Promise.all([
      this.jwt.signAsync(accessPayload, {
        secret: this.config.get('JWT_ACCESS_SECRET', { infer: true }),
        expiresIn: accessTtl,
      }),
      this.jwt.signAsync(refreshPayload, {
        secret: this.config.get('JWT_REFRESH_SECRET', { infer: true }),
        expiresIn: refreshTtl,
      }),
    ]);
    await this.repository.createSession({
      id: sessionId,
      userId: account.id,
      familyId,
      tokenHash: await hash(refreshToken, { type: 2 }),
      expiresAt: new Date(Date.now() + refreshTtl * 1000),
      userAgent: request.headers['user-agent'],
      ipAddress: request.ip,
    }, transaction);
    return { accessToken, refreshToken, expiresIn: accessTtl };
  }
}
