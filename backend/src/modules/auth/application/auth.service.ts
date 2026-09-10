import { BadRequestException, ForbiddenException, Injectable, ServiceUnavailableException, UnauthorizedException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import { hash, verify } from 'argon2';
import bcrypt from 'bcryptjs';
import { randomBytes, randomUUID } from 'node:crypto';
import type { Request } from 'express';
import type { AccessTokenPayload, AuthUser, RefreshTokenPayload } from '../../../common/auth/auth-user.js';
import type { Environment } from '../../../config/environment.js';
import { CamaraNumberVerificationAdapter } from '../../../integrations/camara/number-verification.adapter.js';
import type { RegistrationPendingConfirmation, TokenPair } from '../domain/auth.types.js';
import { AuthRepository } from '../infrastructure/auth.repository.js';
import { AuthActionTokenCipher } from '../infrastructure/auth-action-token-cipher.js';
import { OAuthIdentityVerifier } from '../infrastructure/oauth-identity-verifier.js';
import { PhoneSigninStateRepository, type PhoneSigninIntent } from '../infrastructure/phone-signin-state.repository.js';
import type { LoginDto, OAuthSignInDto, RegisterDto } from '../presentation/auth.dto.js';
import { assertPasswordPolicy } from '../domain/password-policy.js';

/**
 * Signals, from inside the refresh transaction, that the whole session family
 * must be revoked — carrying the family id and the response the caller should
 * receive. Revoking has to happen after the transaction unwinds, because the
 * same conditions that require it also fail the request, and a failed request
 * rolls the transaction back.
 *
 * Not exported: it never leaves `refresh()`, which translates it into its
 * carried `response` before returning to the controller.
 */
class RefreshFamilyCompromised extends Error {
  constructor(
    readonly familyId: string,
    readonly response: UnauthorizedException,
  ) {
    super('Refresh token family compromised');
    this.name = 'RefreshFamilyCompromised';
  }
}

@Injectable()
export class AuthService {
  constructor(
    private readonly repository: AuthRepository,
    private readonly jwt: JwtService,
    private readonly config: ConfigService<Environment, true>,
    private readonly oauthVerifier: OAuthIdentityVerifier,
    private readonly actionTokenCipher: AuthActionTokenCipher,
    private readonly numberVerification: CamaraNumberVerificationAdapter,
    private readonly phoneStates: PhoneSigninStateRepository,
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

  /**
   * Verifies a password against whichever scheme the stored hash uses, and
   * upgrades a legacy hash to argon2 on the way through.
   *
   * The quest-app import brought 180 real accounts whose hashes are bcrypt
   * ($2a$/$2b$). This service hashes with argon2, and argon2's verify returns
   * false for a bcrypt hash rather than throwing — so every one of those
   * users was refused with the correct password and no error to explain it.
   *
   * A successful bcrypt check re-hashes with argon2 and persists it, so each
   * account upgrades on its owner's next sign-in and the bcrypt hash stops
   * existing. Nothing is written when verification fails.
   */
  private async verifyPassword(
    userId: string,
    storedHash: string,
    password: string,
  ): Promise<boolean> {
    if (/^\$2[abxy]?\$/.test(storedHash)) {
      if (!(await bcrypt.compare(password, storedHash))) return false;
      await this.repository.replacePasswordHash(
        userId,
        await hash(password, { type: 2 }),
      );
      return true;
    }
    return verify(storedHash, password);
  }

  async login(input: LoginDto, request: Request): Promise<TokenPair> {
    const account = await this.repository.findAccountByEmail(input.email);
    const valid = account?.passwordHash
      ? await this.verifyPassword(account.id, account.passwordHash, input.password)
      : false;
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

  async linkOAuth(userId: string, input: OAuthSignInDto): Promise<void> {
    const identity = await this.oauthVerifier.verify(
      input.provider, input.idToken, input.nonce, input.displayName,
    );
    await this.repository.linkOAuthIdentity(userId, identity, input.ageVerified);
  }

  /// Starts the CAMARA Number Verification redirect for a brand-new sign-in
  /// (issue #1) — public, no account exists yet.
  ///
  /// `phoneNumber` is only ever a CLAIM at this point. It is recorded so
  /// Number Verification V1 has something to check the device against, and
  /// it is not trusted for anything until the network says it matches.
  startPhoneSignIn(phoneNumber: string, ageVerified: true, email?: string): Promise<{ authorizationUrl: string }> {
    return this.startPhoneFlow('sign_in', phoneNumber, undefined, ageVerified, email);
  }

  /// Same redirect, but to attach a verified phone number to the
  /// already-signed-in caller instead of creating an account.
  startPhoneLink(userId: string, phoneNumber: string): Promise<{ authorizationUrl: string }> {
    return this.startPhoneFlow('link', phoneNumber, userId);
  }

  private async startPhoneFlow(
    intent: PhoneSigninIntent,
    claimedPhoneNumber: string,
    userId?: string,
    ageVerified = false,
    claimedEmail?: string,
  ): Promise<{ authorizationUrl: string }> {
    const redirectUri = this.config.get('CAMARA_NUMBER_VERIFICATION_REDIRECT_URI', { infer: true });
    if (!redirectUri) {
      throw new ServiceUnavailableException({ code: 'PHONE_SIGNIN_NOT_CONFIGURED', message: 'Phone sign-in is not available yet' });
    }
    const state = randomBytes(24).toString('base64url');
    const nonce = randomBytes(24).toString('base64url');
    const { url, flow } = await this.numberVerification.buildAuthorizationUrl({
      state, nonce, redirectUri, loginHint: claimedPhoneNumber,
    });
    await this.phoneStates.start({
      state, intent, userId, ageVerified, redirectUri, nonce, claimedPhoneNumber,
      oauthFlow: flow, claimedEmail, ttlMs: 5 * 60 * 1000,
    });
    return { authorizationUrl: url };
  }

  /// Handles Nokia's redirect back. Never returns tokens directly — hands
  /// the browser a one-time handoff code via a deep link so the mobile app
  /// picks up the result over a normal authenticated POST
  /// (completePhoneHandoff), never embedded in a URL.
  async completePhoneCallback(code: string, state: string): Promise<{ redirectUrl: string }> {
    const pending = await this.phoneStates.consumePending(state);
    if (!pending) {
      throw new BadRequestException({ code: 'INVALID_PHONE_SIGNIN_STATE', message: 'This phone sign-in link is invalid or has expired' });
    }
    // Rows predating migration 0032 carry no claim, so there is nothing for
    // V1 to verify against. Fail closed rather than verify nothing.
    if (!pending.claimedPhoneNumber) {
      throw new BadRequestException({ code: 'INVALID_PHONE_SIGNIN_STATE', message: 'This phone sign-in link is invalid or has expired' });
    }

    const outcome = await this.numberVerification.verifyClaimedNumber({
      code,
      // `state` came back from the operator, but we only reach here after
      // consumePending matched it against a live single-use row, so the
      // value forwarded to Nokia is one we issued.
      state,
      nonce: pending.nonce,
      redirectUri: pending.redirectUri,
      // Rows predating migration 0033 were all standard-flow.
      flow: pending.oauthFlow ?? 'standard',
      claimedPhoneNumber: pending.claimedPhoneNumber,
    });

    // The network's "no" and the network's silence are different answers and
    // get different error codes, so the app can offer "check the number" in
    // one case and "try again" in the other. Neither marks anything verified.
    if (outcome.status === 'NOT_VERIFIED') {
      throw new BadRequestException({
        code: 'PHONE_NUMBER_NOT_VERIFIED',
        message: 'That number could not be verified on this device. Check the number and make sure mobile data is on.',
      });
    }
    if (outcome.status === 'UNAVAILABLE') {
      throw new ServiceUnavailableException({
        code: 'NUMBER_VERIFICATION_UNAVAILABLE',
        message: 'Could not reach the network to verify your number. Please try again.',
      });
    }
    const phoneNumber = outcome.phoneNumber;

    let resultUserId: string;
    if (pending.intent === 'link') {
      if (!pending.userId) {
        throw new BadRequestException({ code: 'INVALID_PHONE_SIGNIN_STATE', message: 'Missing account context' });
      }
      const account = await this.repository.linkPhoneIdentity(pending.userId, phoneNumber);
      resultUserId = account.id;
    } else {
      const account = await this.repository.findOrCreateByPhone(phoneNumber, pending.ageVerified, pending.claimedEmail);
      resultUserId = account.id;
    }

    const mobileRedirectBase = this.config.get('PHONE_SIGNIN_MOBILE_REDIRECT_URL', { infer: true });
    if (!mobileRedirectBase) {
      throw new ServiceUnavailableException({ code: 'PHONE_SIGNIN_NOT_CONFIGURED', message: 'Phone sign-in is not available yet' });
    }
    const handoffCode = randomBytes(24).toString('base64url');
    await this.phoneStates.markCompleted(pending.id, resultUserId, handoffCode, 2 * 60 * 1000);
    const redirectUrl = new URL(mobileRedirectBase);
    redirectUrl.searchParams.set('handoff', handoffCode);
    redirectUrl.searchParams.set('intent', pending.intent);
    return { redirectUrl: redirectUrl.toString() };
  }

  /// The mobile app's side of the handoff: exchange the one-time code from
  /// the deep link for a fresh token pair. Always re-issues, even for
  /// `link` — the caller already had a session, but its access token still
  /// says `phoneVerified: false` until a new one is minted, and the mobile
  /// app's mandatory-verification gate reads that claim client-side.
  async completePhoneHandoff(handoffCode: string, request: Request): Promise<TokenPair> {
    const result = await this.phoneStates.consumeHandoff(handoffCode);
    if (!result) {
      throw new BadRequestException({ code: 'INVALID_PHONE_HANDOFF', message: 'This sign-in attempt is invalid or has expired' });
    }
    const account = await this.repository.findActiveAccountById(result.userId);
    if (!account) throw new UnauthorizedException({ code: 'ACCOUNT_RESTRICTED', message: 'This account is not available' });
    if (result.intent === 'sign_in') await this.repository.touchLastLogin(account.id);
    return this.issueTokenPair(account, request);
  }

  /**
   * Changes the password after re-authenticating, then re-issues a session.
   *
   * The repository revokes every session and bumps `token_version`, so the
   * caller's own access token dies with everyone else's — that is the point,
   * since the whole reason to change a password is to evict somebody. A fresh
   * pair is returned so the device performing the change is not signed out as
   * a side effect of protecting itself.
   */
  async updatePassword(
    userId: string,
    currentPassword: string,
    newPassword: string,
    request: Request,
  ): Promise<TokenPair & { id: string; email: string }> {
    const identity = await this.repository.passwordIdentity(userId);
    if (!identity?.email) throw new UnauthorizedException();

    const credentials = await this.repository.findActiveAccountById(userId);
    if (!credentials?.passwordHash || !(await verify(credentials.passwordHash, currentPassword))) {
      throw new UnauthorizedException({
        code: 'INVALID_CREDENTIALS',
        message: 'The current password is incorrect',
      });
    }

    assertPasswordPolicy(newPassword, identity.username, identity.email);
    const account = await this.repository.updatePassword(userId, await hash(newPassword, { type: 2 }));
    const tokens = await this.issueTokenPair(account, request);
    return { ...tokens, id: account.id, email: account.email ?? identity.email };
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

    // The revocation must not run on the transaction handle: every branch that
    // needs it also needs to fail the request, and DatabaseService.transaction
    // issues ROLLBACK when its callback throws. Previously the revoke and the
    // throw sat on adjacent lines, so the rollback discarded the revoke —
    // token-theft detection reported REFRESH_TOKEN_REUSED and then left every
    // session in the family valid, including the attacker's successor token.
    // So: signal the intent from inside, act on it once the rollback is done.
    try {
      return await this.repository.transaction(async (transaction) => {
        const session = await this.repository.findSessionForUpdate(payload.sid, transaction);
        if (!session || session.revokedAt || session.expiresAt <= new Date()) {
          throw new UnauthorizedException({ code: 'INVALID_REFRESH_SESSION', message: 'Refresh session is no longer valid' });
        }
        if (session.rotatedAt) {
          throw new RefreshFamilyCompromised(session.familyId, new UnauthorizedException({ code: 'REFRESH_TOKEN_REUSED', message: 'Refresh token reuse was detected; sign in again' }));
        }
        if (!(await verify(session.tokenHash, rawToken)) || session.tokenVersion !== payload.tokenVersion) {
          throw new RefreshFamilyCompromised(session.familyId, new UnauthorizedException({ code: 'INVALID_REFRESH_TOKEN', message: 'Refresh token is invalid' }));
        }
        const account = await this.repository.findActiveAccountById(session.userId);
        if (!account || account.tokenVersion !== payload.tokenVersion) {
          throw new RefreshFamilyCompromised(session.familyId, new UnauthorizedException({ code: 'SESSION_REVOKED', message: 'Session has been revoked' }));
        }
        await this.repository.markSessionRotated(session.id, transaction);
        return this.issueTokenPair(account, request, session.familyId, transaction);
      });
    } catch (error) {
      if (error instanceof RefreshFamilyCompromised) {
        // No transaction argument, so this runs on the pool and commits.
        await this.repository.revokeFamily(error.familyId);
        throw error.response;
      }
      throw error;
    }
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
      phoneVerified: account.phoneVerified,
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
