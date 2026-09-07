import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import type { Request } from 'express';
import type { Environment } from '../../../config/environment.js';
import type { RegistrationPendingConfirmation, TokenPair } from '../domain/auth.types.js';
import { AuthRepository } from '../infrastructure/auth.repository.js';
import { AuthActionTokenCipher } from '../infrastructure/auth-action-token-cipher.js';
import { OAuthIdentityVerifier } from '../infrastructure/oauth-identity-verifier.js';
import type { LoginDto, OAuthSignInDto, RegisterDto } from '../presentation/auth.dto.js';
export declare class AuthService {
    private readonly repository;
    private readonly jwt;
    private readonly config;
    private readonly oauthVerifier;
    private readonly actionTokenCipher;
    constructor(repository: AuthRepository, jwt: JwtService, config: ConfigService<Environment, true>, oauthVerifier: OAuthIdentityVerifier, actionTokenCipher: AuthActionTokenCipher);
    register(input: RegisterDto, request: Request): Promise<TokenPair | RegistrationPendingConfirmation>;
    login(input: LoginDto, request: Request): Promise<TokenPair>;
    oauth(input: OAuthSignInDto, request: Request): Promise<TokenPair>;
    updatePassword(userId: string, newPassword: string): Promise<{
        id: string;
        email: string;
    }>;
    requestPasswordRecovery(email: string): Promise<void>;
    completePasswordRecovery(token: string, newPassword: string): Promise<void>;
    requestEmailConfirmation(email: string): Promise<void>;
    completeEmailConfirmation(token: string): Promise<void>;
    refresh(rawToken: string, request: Request): Promise<TokenPair>;
    logout(rawToken?: string): Promise<void>;
    private invalidRecoveryToken;
    private issueTokenPair;
}
