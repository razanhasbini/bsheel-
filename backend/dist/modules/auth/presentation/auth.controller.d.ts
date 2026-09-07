import type { Request } from 'express';
import type { AuthUser } from '../../../common/auth/auth-user.js';
import { AuthService } from '../application/auth.service.js';
import type { RegistrationPendingConfirmation, TokenPair } from '../domain/auth.types.js';
import { CompleteEmailConfirmationDto, CompletePasswordRecoveryDto, LoginDto, LogoutDto, OAuthSignInDto, RefreshTokenDto, RegisterDto, RequestEmailConfirmationDto, RequestPasswordRecoveryDto, UpdatePasswordDto } from './auth.dto.js';
export declare class AuthController {
    private readonly service;
    constructor(service: AuthService);
    register(body: RegisterDto, request: Request): Promise<TokenPair | RegistrationPendingConfirmation>;
    login(body: LoginDto, request: Request): Promise<TokenPair>;
    oauth(body: OAuthSignInDto, request: Request): Promise<TokenPair>;
    updatePassword(user: AuthUser, body: UpdatePasswordDto): Promise<{
        id: string;
        email: string;
    }>;
    requestPasswordRecovery(body: RequestPasswordRecoveryDto): Promise<void>;
    completePasswordRecovery(body: CompletePasswordRecoveryDto): Promise<void>;
    requestEmailConfirmation(body: RequestEmailConfirmationDto): Promise<void>;
    completeEmailConfirmation(body: CompleteEmailConfirmationDto): Promise<void>;
    refresh(body: RefreshTokenDto, request: Request): Promise<TokenPair>;
    logout(_user: AuthUser, body: LogoutDto): Promise<void>;
}
