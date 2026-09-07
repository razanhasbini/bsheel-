import { Module } from '@nestjs/common';
import { JwtModule } from '@nestjs/jwt';
import { PassportModule } from '@nestjs/passport';
import { AuthService } from './application/auth.service.js';
import { AccessTokenStrategy } from './infrastructure/access-token.strategy.js';
import { AuthActionTokenCipher } from './infrastructure/auth-action-token-cipher.js';
import { AuthRepository } from './infrastructure/auth.repository.js';
import { OAuthIdentityVerifier } from './infrastructure/oauth-identity-verifier.js';
import { AuthController } from './presentation/auth.controller.js';

@Module({
  imports: [PassportModule, JwtModule.register({})],
  controllers: [AuthController],
  providers: [
    AuthService,
    AuthRepository,
    OAuthIdentityVerifier,
    AuthActionTokenCipher,
    AccessTokenStrategy,
  ],
  exports: [AuthService, AuthRepository, AuthActionTokenCipher],
})
export class AuthModule {}
