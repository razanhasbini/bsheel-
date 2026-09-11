import { Module } from '@nestjs/common';
import { JwtModule } from '@nestjs/jwt';
import { PassportModule } from '@nestjs/passport';
import { CamaraModule } from '../../integrations/camara/camara.module.js';
import { AuthService } from './application/auth.service.js';
import { AccessTokenStrategy } from './infrastructure/access-token.strategy.js';
import { AuthActionTokenCipher } from './infrastructure/auth-action-token-cipher.js';
import { AuthRepository } from './infrastructure/auth.repository.js';
import { OAuthIdentityVerifier } from './infrastructure/oauth-identity-verifier.js';
import { PhoneSigninStateRepository } from './infrastructure/phone-signin-state.repository.js';
import { AuthController } from './presentation/auth.controller.js';
import { PhoneSigninLandingController } from './presentation/phone-signin-landing.controller.js';

@Module({
  imports: [PassportModule, JwtModule.register({}), CamaraModule],
  controllers: [AuthController, PhoneSigninLandingController],
  providers: [
    AuthService,
    AuthRepository,
    OAuthIdentityVerifier,
    AuthActionTokenCipher,
    AccessTokenStrategy,
    PhoneSigninStateRepository,
  ],
  exports: [AuthService, AuthRepository, AuthActionTokenCipher],
})
export class AuthModule {}
