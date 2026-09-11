import { Type } from 'class-transformer';
import { IsInt, IsISO8601, IsOptional, IsUUID, Max, Min } from 'class-validator';

export class BusinessDailyQueryDto {
  /// Bounded at 365: the window is a generate_series, so an unbounded value
  /// would build an arbitrarily large table on the server to answer one
  /// chart request.
  @IsOptional() @Type(() => Number) @IsInt() @Min(1) @Max(365) days = 30;
}

export class BusinessQuestQueryDto {
  @IsOptional() @Type(() => Number) @IsInt() @Min(1) @Max(100) limit = 50;
  @IsOptional() @Type(() => Number) @IsInt() @Min(0) @Max(100000) offset = 0;
}

/// Keyset cursor. Both fields or neither — the service rejects half of one
/// rather than quietly dropping it and returning page one again.
export class BusinessProofQueryDto {
  @IsOptional() @Type(() => Number) @IsInt() @Min(1) @Max(50) limit = 20;
  @IsOptional() @IsISO8601() beforeSubmittedAt?: string;
  @IsOptional() @IsUUID() beforeId?: string;
}
