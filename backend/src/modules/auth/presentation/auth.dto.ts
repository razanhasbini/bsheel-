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
  // Re-authentication is required. Without it, anyone holding an access token
  // — a briefly unlocked phone, a token from a log line — took the account
  // permanently, and the victim's own "change my password" did not evict them
  // because no session was invalidated either.
  //
  // No @MinLength here: this is compared against the stored hash, not created,
  // and a length rule on it would leak the old policy.
  @IsString() currentPassword!: string;

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
