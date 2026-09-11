import { Equals, IsBoolean, IsEmail, IsIn, IsOptional, IsString, Length, Matches, MaxLength, MinLength, ValidateIf } from 'class-validator';

/**
 * E.164: a leading '+', a non-zero country code, then digits. Number
 * Verification V1 requires this exact shape, and Nokia's simulator
 * identities (+99999991000 / +99999991001) are E.164 too, so there is no
 * separate test-number carve-out to maintain.
 *
 * Validating here keeps a malformed number from ever reaching Nokia, but it
 * proves nothing about ownership — that is entirely the network's answer.
 */
const E164 = /^\+[1-9]\d{6,14}$/;

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

/**
 * Sign in with a password and exactly one identifier.
 *
 * Phone is the account's primary credential — it is what CAMARA verified and
 * what every phone sign-up creates — so `phoneNumber` is what the app sends.
 * `email` stays accepted because the 180 imported password accounts have no
 * phone number at all and would otherwise be locked out.
 *
 * "Exactly one" is enforced rather than "at least one": accepting both would
 * leave the service picking a winner, and which identifier was checked is
 * precisely what decides whether email or phone verification gates the login.
 */
export class LoginDto {
  @IsOptional() @IsEmail() email?: string;

  @IsOptional()
  @Matches(E164, { message: 'phoneNumber must be in international format, e.g. +96170123456' })
  phoneNumber?: string;

  @IsString()
  password!: string;

  @ValidateIf((dto: LoginDto) => (dto.email == null) === (dto.phoneNumber == null))
  @Equals('__exactly_one_identifier__', {
    message: 'Provide either an email or a phone number, not both',
  })
  readonly identifierGuard?: never;
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

export class StartPhoneSignInDto {
  @Matches(E164, { message: 'phoneNumber must be in international format, e.g. +96170123456' })
  phoneNumber!: string;

  /// Optional. Phone is the credential; an email is only a contact and
  /// recovery address, and the account is created without one if omitted.
  @IsOptional() @IsEmail() email?: string;

  /// Optional only because `phone/start` also serves an existing account
  /// signing back in, which already has one. The signup form always sends
  /// it, and the policy check in the service is what actually rejects a
  /// weak choice — the length bound here just keeps absurd input out of the
  /// hasher.
  @IsOptional() @IsString() @MinLength(10) @MaxLength(200) password?: string;

  @Equals(true) ageVerified!: true;
}

export class StartPhoneLinkDto {
  @Matches(E164, { message: 'phoneNumber must be in international format, e.g. +96170123456' })
  phoneNumber!: string;
}

export class PhoneCallbackDto {
  @IsString() @MinLength(1) code!: string;
  @IsString() @MinLength(1) state!: string;
}

export class CompletePhoneHandoffDto {
  @IsString() @MinLength(1) handoffCode!: string;
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
