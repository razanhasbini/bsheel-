import { Type } from 'class-transformer';
import { IsInt, IsISO8601, IsOptional, IsUUID, Matches, Max, Min } from 'class-validator';

export class BusinessDailyQueryDto {
  /// A rolling window ending today. Bounded because the series is one row
  /// per day: an unbounded value would build an arbitrarily large table on
  /// the server to answer one chart request.
  @IsOptional() @Type(() => Number) @IsInt() @Min(1) @Max(366) days = 30;

  /// An explicit range instead, inclusive, `YYYY-MM-DD`. Supplying either
  /// end overrides [days] — a caller that sent both meant the range, and
  /// quietly drawing the rolling window would chart dates they did not ask
  /// about. The span bound and the reversed-range check live in
  /// `resolveDailyWindow`, so the reason reaches the caller.
  @IsOptional() @Matches(/^\d{4}-\d{2}-\d{2}$/) from?: string;
  @IsOptional() @Matches(/^\d{4}-\d{2}-\d{2}$/) to?: string;
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
