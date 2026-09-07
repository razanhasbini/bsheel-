import { IsBoolean, IsOptional, IsString, Length, Matches } from 'class-validator';

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
}

export class AnalyticsConsentDto {
  @IsBoolean()
  consented!: boolean;
}
