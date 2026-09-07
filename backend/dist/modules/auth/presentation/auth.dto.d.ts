export declare class RegisterDto {
    email: string;
    password: string;
    username: string;
    displayName: string;
    ageVerified: boolean;
}
export declare class LoginDto {
    email: string;
    password: string;
}
export declare class RefreshTokenDto {
    refreshToken: string;
}
export declare class LogoutDto {
    refreshToken?: string;
}
export declare class OAuthSignInDto {
    provider: 'google' | 'apple';
    idToken: string;
    nonce?: string;
    displayName?: string;
    ageVerified: true;
}
export declare class UpdatePasswordDto {
    newPassword: string;
}
export declare class RequestPasswordRecoveryDto {
    email: string;
}
export declare class CompletePasswordRecoveryDto {
    token: string;
    newPassword: string;
}
export declare class RequestEmailConfirmationDto {
    email: string;
}
export declare class CompleteEmailConfirmationDto {
    token: string;
}
