import { Type } from 'class-transformer';
import {
  IsBoolean,
  IsEmail,
  IsIn,
  IsInt,
  IsOptional,
  IsString,
  IsUrl,
  IsUUID,
  Matches,
  Max,
  MaxLength,
  Min,
  MinLength,
} from 'class-validator';
import { businessMemberRoles, businessStatuses } from '../domain/business.js';

export class BusinessIdDto {
  @IsUUID() businessId!: string;
}

export class BusinessPlaceParamsDto {
  @IsUUID() businessId!: string;
  @IsUUID() placeId!: string;
}

export class BusinessMemberParamsDto {
  @IsUUID() businessId!: string;
  @IsUUID() userId!: string;
}

export class BusinessListQueryDto {
  @IsOptional() @Type(() => Number) @IsInt() @Min(1) @Max(100) limit = 50;
  @IsOptional() @Type(() => Number) @IsInt() @Min(0) @Max(100000) offset = 0;
}

export class CreateBusinessDto {
  @IsString() @MinLength(2) @MaxLength(120) name!: string;
  /// Optional: derived from the name when omitted. The pattern mirrors the
  /// column's CHECK exactly, so an invalid handle is a 400 from validation
  /// rather than a constraint violation surfacing as a 500.
  @IsOptional() @Matches(/^[a-z0-9][a-z0-9-]{1,62}[a-z0-9]$/) slug?: string;
  @IsOptional() @IsString() @MaxLength(2000) description?: string;
  @IsOptional() @IsEmail() @MaxLength(320) contactEmail?: string;
  @IsOptional() @IsUrl({ protocols: ['http', 'https'], require_protocol: true }) @MaxLength(2048) websiteUrl?: string;
  @IsOptional() @IsUrl({ protocols: ['http', 'https'], require_protocol: true }) @MaxLength(2048) logoUrl?: string;
  /// The first owner. Required, because a business with no owner is
  /// unreachable: only an owner may appoint members.
  @IsUUID() ownerUserId!: string;
}

/// Every field optional — an admin flipping `status` alone should not have
/// to resend the whole record. `null` on a nullable field clears it, which
/// is why those are not merely optional.
export class UpdateBusinessDto {
  @IsOptional() @IsString() @MinLength(2) @MaxLength(120) name?: string;
  @IsOptional() @IsString() @MaxLength(2000) description?: string;
  @IsOptional() @IsEmail() @MaxLength(320) contactEmail?: string | null;
  @IsOptional() @IsUrl({ protocols: ['http', 'https'], require_protocol: true }) @MaxLength(2048) websiteUrl?: string | null;
  @IsOptional() @IsUrl({ protocols: ['http', 'https'], require_protocol: true }) @MaxLength(2048) logoUrl?: string | null;
  @IsOptional() @IsIn(businessStatuses) status?: (typeof businessStatuses)[number];
  /// #50's whitelist. True stamps the subscription now, false clears it.
  /// Separate from `status`: suspending a business for a content dispute is
  /// not the same act as ending its analytics subscription.
  @IsOptional() @IsBoolean() analyticsSubscribed?: boolean;
}

export class LinkBusinessPlaceDto {
  @IsUUID() placeId!: string;
}

export class AddBusinessMemberDto {
  @IsUUID() userId!: string;
  @IsIn(businessMemberRoles) role: (typeof businessMemberRoles)[number] = 'manager';
}
