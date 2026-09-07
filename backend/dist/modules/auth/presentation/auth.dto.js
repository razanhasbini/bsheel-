var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
var __metadata = (this && this.__metadata) || function (k, v) {
    if (typeof Reflect === "object" && typeof Reflect.metadata === "function") return Reflect.metadata(k, v);
};
import { Equals, IsBoolean, IsEmail, IsIn, IsOptional, IsString, Length, Matches, MaxLength, MinLength } from 'class-validator';
export class RegisterDto {
    email;
    password;
    username;
    displayName;
    ageVerified;
}
__decorate([
    IsEmail(),
    __metadata("design:type", String)
], RegisterDto.prototype, "email", void 0);
__decorate([
    IsString(),
    MinLength(10),
    __metadata("design:type", String)
], RegisterDto.prototype, "password", void 0);
__decorate([
    IsString(),
    Matches(/^[a-zA-Z0-9_]+$/),
    Length(3, 30),
    __metadata("design:type", String)
], RegisterDto.prototype, "username", void 0);
__decorate([
    IsString(),
    Length(1, 50),
    __metadata("design:type", String)
], RegisterDto.prototype, "displayName", void 0);
__decorate([
    IsBoolean(),
    __metadata("design:type", Boolean)
], RegisterDto.prototype, "ageVerified", void 0);
export class LoginDto {
    email;
    password;
}
__decorate([
    IsEmail(),
    __metadata("design:type", String)
], LoginDto.prototype, "email", void 0);
__decorate([
    IsString(),
    __metadata("design:type", String)
], LoginDto.prototype, "password", void 0);
export class RefreshTokenDto {
    refreshToken;
}
__decorate([
    IsString(),
    __metadata("design:type", String)
], RefreshTokenDto.prototype, "refreshToken", void 0);
export class LogoutDto {
    refreshToken;
}
__decorate([
    IsOptional(),
    IsString(),
    __metadata("design:type", String)
], LogoutDto.prototype, "refreshToken", void 0);
export class OAuthSignInDto {
    provider;
    idToken;
    nonce;
    displayName;
    ageVerified;
}
__decorate([
    IsIn(['google', 'apple']),
    __metadata("design:type", String)
], OAuthSignInDto.prototype, "provider", void 0);
__decorate([
    IsString(),
    MinLength(100),
    __metadata("design:type", String)
], OAuthSignInDto.prototype, "idToken", void 0);
__decorate([
    IsOptional(),
    IsString(),
    Length(16, 200),
    __metadata("design:type", String)
], OAuthSignInDto.prototype, "nonce", void 0);
__decorate([
    IsOptional(),
    IsString(),
    MaxLength(100),
    __metadata("design:type", String)
], OAuthSignInDto.prototype, "displayName", void 0);
__decorate([
    Equals(true),
    __metadata("design:type", Boolean)
], OAuthSignInDto.prototype, "ageVerified", void 0);
export class UpdatePasswordDto {
    newPassword;
}
__decorate([
    IsString(),
    MinLength(10),
    __metadata("design:type", String)
], UpdatePasswordDto.prototype, "newPassword", void 0);
export class RequestPasswordRecoveryDto {
    email;
}
__decorate([
    IsEmail(),
    __metadata("design:type", String)
], RequestPasswordRecoveryDto.prototype, "email", void 0);
export class CompletePasswordRecoveryDto {
    token;
    newPassword;
}
__decorate([
    IsString(),
    MinLength(32),
    __metadata("design:type", String)
], CompletePasswordRecoveryDto.prototype, "token", void 0);
__decorate([
    IsString(),
    MinLength(10),
    __metadata("design:type", String)
], CompletePasswordRecoveryDto.prototype, "newPassword", void 0);
export class RequestEmailConfirmationDto {
    email;
}
__decorate([
    IsEmail(),
    __metadata("design:type", String)
], RequestEmailConfirmationDto.prototype, "email", void 0);
export class CompleteEmailConfirmationDto {
    token;
}
__decorate([
    IsString(),
    MinLength(32),
    __metadata("design:type", String)
], CompleteEmailConfirmationDto.prototype, "token", void 0);
//# sourceMappingURL=auth.dto.js.map