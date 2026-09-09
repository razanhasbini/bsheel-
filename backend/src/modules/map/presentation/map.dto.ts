import { Type } from 'class-transformer';
import { IsBoolean, IsIn, IsInt, IsNumber, IsOptional, IsString, IsUUID, Matches, Max, MaxLength, Min, MinLength } from 'class-validator';

export class MapQueryDto {
  @IsOptional() @IsIn(['true','false']) saved?: string;
  @IsOptional() @Matches(/^[A-Z]{2}$/) country?: string;
  @IsOptional() @IsString() @MaxLength(100) search?: string;
  @IsOptional() @IsIn(['landmark', 'culture', 'pilgrimage', 'heritage', 'hidden']) category?: string;
  @IsOptional() @Type(() => Number) @IsInt() @Min(1) @Max(100) limit = 100;
  @IsOptional() @Type(() => Number) @IsInt() @Min(0) @Max(100000) offset = 0;
}
export class MapIdDto { @IsUUID() id!: string; }
export class MapPlaceDto {
  @Matches(/^[A-Z]{2}$/) countryCode!: string;
  @IsString() @MinLength(1) @MaxLength(100) countryName!: string;
  @Matches(/^[0-9]{3}$/) geometryId!: string;
  @IsString() @MinLength(1) @MaxLength(160) name!: string;
  @IsString() @MaxLength(2000) description = '';
  @IsString() @MaxLength(100) city = '';
  @IsIn(['landmark', 'culture', 'pilgrimage', 'heritage', 'hidden']) category!: string;
  @IsNumber() @Min(-85) @Max(85) latitude!: number;
  @IsNumber() @Min(-180) @Max(180) longitude!: number;
  @IsInt() @Min(25) @Max(10000) radiusM = 250;
  @IsBoolean() isPublished = false;
}
export class MapQuestLinkDto {
  @IsUUID() questId!: string;
  @IsBoolean() requiresVerification = true;
}

/// Partial update of a place. Every field optional so a caller can flip
/// `isPublished` alone; bounds mirror MapPlaceDto exactly, because a value
/// that was illegal at creation is still illegal on update.
export class MapPlaceUpdateDto {
  @IsOptional() @IsString() @MinLength(1) @MaxLength(160) name?: string;
  @IsOptional() @IsString() @MaxLength(2000) description?: string;
  @IsOptional() @IsString() @MaxLength(100) city?: string;
  @IsOptional() @IsIn(['landmark', 'culture', 'pilgrimage', 'heritage', 'hidden']) category?: string;
  @IsOptional() @IsNumber() @Min(-85) @Max(85) latitude?: number;
  @IsOptional() @IsNumber() @Min(-180) @Max(180) longitude?: number;
  @IsOptional() @IsInt() @Min(25) @Max(10000) radiusM?: number;
  @IsOptional() @IsBoolean() isPublished?: boolean;
}

/// Path params for unlinking, which needs both ids.
export class MapLinkParamsDto {
  @IsUUID() id!: string;
  @IsUUID() questId!: string;
}
