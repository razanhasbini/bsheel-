import { Transform, Type } from 'class-transformer';
import { Equals, IsBoolean, IsDefined, IsEmail, IsIn, IsInt, IsOptional, IsString, IsUUID, Length, Matches, Max, MaxLength, Min, MinLength } from 'class-validator';

export class AdminListQueryDto {
  @IsOptional() @Type(() => Number) @IsInt() @Min(1) @Max(200) limit = 50;
  @IsOptional() @Type(() => Number) @IsInt() @Min(0) offset = 0;
  @IsOptional() @Transform(({ value }) => typeof value === 'string' ? value.trim() : value) @IsString() @MaxLength(120) q?: string;
}

/**
 * The XP reconciliation audit, which reads a whole page at a time.
 *
 * Separate from AdminListQueryDto because its ceiling differs: the repository
 * clamps this query to 500 and the dashboard asks for 500, but the shared DTO
 * capped it at 200 — so every load of the XP page returned 400 and the page
 * never rendered. Raising the shared cap would have loosened /admin/users too,
 * hence its own type.
 */
export class XpAuditQueryDto {
  @IsOptional() @Type(() => Number) @IsInt() @Min(1) @Max(500) limit = 50;
  @IsOptional() @Type(() => Number) @IsInt() @Min(0) offset = 0;
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
  /**
   * Bounded well below int4's ceiling on purpose.
   *
   * There was no upper bound, so a total could be set high enough that the
   * user's next approval overflowed `xp = xp + award` and the approve
   * endpoint answered 500 with SQLSTATE 22003 — a moderator's click failing
   * because of an unrelated admin edit made days earlier. A hundred million
   * leaves four orders of magnitude of headroom over any real balance.
   */
  @IsInt() @Min(0) @Max(100_000_000) xp!: number;

  /**
   * Accepted for compatibility and then ignored — the level is derived from
   * xp, because the two were independent and nothing checked they agreed.
   * A mismatched pair made `xp_to_next_level` negative and the profile panel
   * render "300 / 200". The admin UI already derives it the same way.
   */
  @IsOptional() @IsInt() @Min(1) level?: number;

  @IsInt() @Min(0) @Max(1_000_000) questsCompleted!: number;
  @IsString() @Length(3, 500) reason!: string;
}

export class UpdateUserProfileDto {
  @IsOptional() @IsString() @Matches(/^[a-z0-9_]{3,30}$/i) username?: string;
  @IsOptional() @IsString() @Length(1, 50) displayName?: string;
  @IsOptional() @IsString() @MaxLength(300) bio?: string;
  @IsOptional() @IsInt() @Min(0) xp?: number;
  @IsOptional() @IsInt() @Min(1) level?: number;
  @IsOptional() @IsInt() @Min(0) questsCompleted?: number;
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
