import { Transform, Type } from 'class-transformer';
import { Equals, IsBoolean, IsDefined, IsEmail, IsIn, IsInt, IsOptional, IsString, IsUUID, Length, Matches, Max, MaxLength, Min, MinLength } from 'class-validator';

export class AdminListQueryDto {
  @IsOptional() @Type(() => Number) @IsInt() @Min(1) @Max(200) limit = 50;
  @IsOptional() @Type(() => Number) @IsInt() @Min(0) offset = 0;
  @IsOptional() @Transform(({ value }) => typeof value === 'string' ? value.trim() : value) @IsString() @MaxLength(120) q?: string;
}

export class ReportsQueryDto extends AdminListQueryDto {
  @IsOptional() @IsIn(['pending', 'reviewed', 'dismissed', 'actioned', 'all']) status = 'pending';
}

export class SuggestionsQueryDto extends AdminListQueryDto {
  @IsOptional() @IsIn(['pending', 'approved', 'rejected', 'all']) status = 'pending';
}

export class UserIdParam { @IsUUID() id!: string; }
export class ConfigKeyParam { @Matches(/^[a-z][a-z0-9_.-]{1,99}$/) key!: string; }

export class SetAccountStatusDto {
  @IsIn(['active', 'suspended', 'banned']) status!: 'active' | 'suspended' | 'banned';
  @IsString() @Length(3, 500) reason!: string;
}

export class CreateUserDto {
  @IsEmail() email!: string;
  @IsString() @MinLength(10) password!: string;
  @IsString() @Matches(/^[a-zA-Z0-9_]+$/) @Length(3, 30) username!: string;
  @IsOptional() @IsString() @Length(1, 50) displayName?: string;
}

export class SetAdminRoleDto {
  @IsOptional() @IsIn(['moderator', 'super_admin'])
  role?: 'moderator' | 'super_admin';
}

export class ForceResetPasswordDto {
  @IsString() @MinLength(10) newPassword!: string;
  @Equals(true) confirm!: true;
}

export class SetUserXpDto {
  @IsInt() @Min(0) xp!: number;
  @IsInt() @Min(1) level!: number;
  @IsInt() @Min(0) questsCompleted!: number;
  @IsString() @Length(3, 500) reason!: string;
}

export class ReviewReportDto {
  @IsIn(['reviewed', 'dismissed', 'actioned']) status!: 'reviewed' | 'dismissed' | 'actioned';
  @IsOptional() @IsString() @MaxLength(2000) adminNote?: string;
}

export class RemovePostDto {
  @IsString() @Length(3, 500) reason!: string;
}

export class InjectQuestDto {
  @IsUUID() targetUserId!: string;
  @IsString() @Length(1, 100) title!: string;
  @IsString() @Length(1, 500) description!: string;
  @IsString() @Length(1, 80) category!: string;
  @IsIn(['easy', 'medium', 'hard']) difficulty!: 'easy' | 'medium' | 'hard';
  @IsInt() @Min(5) @Max(1000) xpReward!: number;
  @IsInt() @Min(1) @Max(168) durationHours!: number;
}

export class SendNotificationDto {
  @IsOptional() @IsUUID() targetUserId?: string;
  @IsString() @Length(1, 180) title!: string;
  @IsString() @Length(1, 500) body!: string;
  @IsOptional() @IsString() @Length(1, 80) type = 'announcement';
}

export class SetConfigDto {
  @IsDefined() value!: unknown;
  @IsOptional() @IsString() @MaxLength(500) description?: string;
  @IsOptional() @IsBoolean() isPublic = false;
}

export class SetQotdDto {
  @IsUUID() questId!: string;
  @Matches(/^\d{4}-\d{2}-\d{2}$/) displayDate!: string;
  @IsOptional() @IsString() @MaxLength(80) ticketNo?: string;
  @IsOptional() @IsInt() @Min(0) @Max(10000) bonusXp = 0;
  @IsOptional() @IsString() @MaxLength(1000) note?: string;
}

export class SuggestionStatusDto {
  @IsIn(['approved', 'rejected']) status!: 'approved' | 'rejected';
  @IsOptional() @IsInt() @Min(5) @Max(1000) xpReward = 50;
  @IsOptional() @IsInt() @Min(1) @Max(168) durationHours = 4;
}
