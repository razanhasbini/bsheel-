import { Equals, IsBoolean, IsEmail, IsIn, IsOptional, IsString, Length, Matches, MaxLength, MinLength } from 'class-validator';

export class RegisterDto {
  @IsEmail()
  email!: string;

  @IsString()
  @MinLength(10)
  password!: string;

  @IsString()
  @Matches(/^[a-zA-Z0-9_]+$/)
  @Length(3, 30)
  username!: string;

  @IsString()
  @Length(1, 50)
  displayName!: string;

  @IsBoolean()
  ageVerified!: boolean;
}

export class LoginDto {
  @IsEmail()
  email!: string;

  @IsString()
  password!: string;
}

export class RefreshTokenDto {
  @IsString()
  refreshToken!: string;
}

export class LogoutDto {
  @IsOptional()
  @IsString()
  refreshToken?: string;
}

export class OAuthSignInDto {
  @IsIn(['google', 'apple']) provider!: 'google' | 'apple';
  @IsString() @MinLength(100) idToken!: string;
  @IsOptional() @IsString() @Length(16, 200) nonce?: string;
  @IsOptional() @IsString() @MaxLength(100) displayName?: string;
  @Equals(true) ageVerified!: true;
}

export class UpdatePasswordDto {
  @IsString() @MinLength(10) newPassword!: string;
}

export class RequestPasswordRecoveryDto {
  @IsEmail() email!: string;
}

export class CompletePasswordRecoveryDto {
  @IsString() @MinLength(32) token!: string;
  @IsString() @MinLength(10) newPassword!: string;
}

export class RequestEmailConfirmationDto {
  @IsEmail() email!: string;
}

export class CompleteEmailConfirmationDto {
  @IsString() @MinLength(32) token!: string;
}
