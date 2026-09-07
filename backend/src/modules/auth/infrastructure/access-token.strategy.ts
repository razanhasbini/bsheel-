import { Injectable, UnauthorizedException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { PassportStrategy } from '@nestjs/passport';
import { ExtractJwt, Strategy } from 'passport-jwt';
import type { AccessTokenPayload, AuthUser } from '../../../common/auth/auth-user.js';
import type { Environment } from '../../../config/environment.js';
import { AuthRepository } from './auth.repository.js';

@Injectable()
export class AccessTokenStrategy extends PassportStrategy(Strategy, 'jwt') {
  constructor(
    config: ConfigService<Environment, true>,
    private readonly repository: AuthRepository,
  ) {
    super({
      jwtFromRequest: ExtractJwt.fromAuthHeaderAsBearerToken(),
      secretOrKey: config.get('JWT_ACCESS_SECRET', { infer: true }),
      ignoreExpiration: false,
    });
  }

  async validate(payload: AccessTokenPayload): Promise<AuthUser> {
    if (payload.type !== 'access') throw new UnauthorizedException();
    const account = await this.repository.findActiveAccountById(payload.sub);
    if (!account || account.tokenVersion !== payload.tokenVersion) {
      throw new UnauthorizedException({ code: 'SESSION_REVOKED', message: 'Session is no longer valid' });
    }
    return { id: account.id, email: account.email, role: account.role, tokenVersion: account.tokenVersion };
  }
}

