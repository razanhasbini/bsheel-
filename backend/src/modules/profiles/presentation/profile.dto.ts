import { Equals, IsBoolean, IsOptional, IsString, Length, Matches } from 'class-validator';

export class UpdateProfileDto {
  @IsOptional()
  @IsString()
  @Matches(/^[a-zA-Z0-9_]+$/)
  @Length(3, 30)
  username?: string;

  @IsOptional()
  @IsString()
  @Length(1, 50)
  displayName?: string;

  @IsOptional()
  @IsString()
  @Matches(/^avatars\/[0-9a-f-]{36}\/[A-Za-z0-9._-]+$/i)
  avatarUrl?: string | null;

  @IsOptional()
  @IsString()
  @Length(0, 300)
  bio?: string | null;

  @IsOptional()
  @IsBoolean()
  profileCompleted?: boolean;

  /// Self-declared home country, ISO 3166-1 alpha-2. Optional, and null
  /// clears it. Accepts either case and is normalised on write, so a client
  /// sending "lb" is not a validation error the user has to decode.
  ///
  /// Never shown on a public profile. It exists so business analytics can
  /// answer "where do visitors come from" in aggregate, and only for users
  /// who have also given analytics consent.
  @IsOptional()
  @IsString()
  @Matches(/^[A-Za-z]{2}$/)
  countryCode?: string | null;

  /// The one-time 13+ confirmation the app asks after sign-in for any
  /// account that has not given it yet (phone, Google and Apple sign-in no
  /// longer ask up front). Only `true` is accepted: the flag is monotonic,
  /// and a client cannot un-confirm an age on someone's behalf.
  @IsOptional()
  @Equals(true)
  ageVerified?: true;
}

export class AnalyticsConsentDto {
  @IsBoolean()
  consented!: boolean;
}
