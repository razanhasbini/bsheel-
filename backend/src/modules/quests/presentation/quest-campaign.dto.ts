import { IsBoolean, IsIn, IsInt, IsOptional, IsString, IsUUID, Length, Matches, Min } from 'class-validator';

/// Chain and collection DTOs (#56).
///
/// Lengths mirror the CHECK constraints from migration 0024 rather than
/// inventing their own, so a value the API accepts is one the database will
/// also accept — the alternative is a 500 where a 400 belongs.

export class CreateChainDto {
  @IsString() @Length(1, 160) name!: string;
  @IsOptional() @IsString() @Length(0, 2000) description = '';
  /// 'solo': one player completes every step. 'group': an approved step
  /// unlocks the next member's. The difference is who the next step is
  /// offered to, which is why it is a property of the chain.
  @IsOptional() @IsIn(['solo', 'group']) mode: 'solo' | 'group' = 'solo';
  @IsOptional() @IsBoolean() isActive = true;
}

export class UpdateChainDto {
  @IsOptional() @IsString() @Length(1, 160) name?: string;
  @IsOptional() @IsString() @Length(0, 2000) description?: string;
  @IsOptional() @IsIn(['solo', 'group']) mode?: 'solo' | 'group';
  @IsOptional() @IsBoolean() isActive?: boolean;
}

export class CreateCollectionDto {
  @IsString() @Length(1, 160) name!: string;
  @IsOptional() @IsString() @Length(0, 2000) description = '';
  /// Optional so a campaign need not be tied to one country. Must be a code
  /// `map_countries` knows; the FK is the real guard.
  @IsOptional() @Matches(/^[A-Z]{2}$/, { message: 'countryCode must be a two-letter uppercase country code' })
  countryCode?: string;
  @IsOptional() @IsBoolean() isPublished = false;
}

export class UpdateCollectionDto {
  @IsOptional() @IsString() @Length(1, 160) name?: string;
  @IsOptional() @IsString() @Length(0, 2000) description?: string;
  /// An empty string clears the country; omitting the field leaves it alone.
  @IsOptional() @Matches(/^([A-Z]{2})?$/, { message: 'countryCode must be a two-letter uppercase country code, or empty to clear it' })
  countryCode?: string;
  @IsOptional() @IsBoolean() isPublished?: boolean;
}

export class CampaignQuestDto {
  @IsUUID() questId!: string;
}

export class ReorderStepDto {
  @IsUUID() questId!: string;
  /// 1-based, matching `quest_chain_steps.step_order`. Clamped server-side to
  /// the chain's length, so an out-of-range value moves the step to an end
  /// rather than failing.
  @IsInt() @Min(1) toOrder!: number;
}

export class CampaignIdParam {
  @IsUUID() id!: string;
}

export class CampaignQuestParams {
  @IsUUID() id!: string;
  @IsUUID() questId!: string;
}

export class AssignableQuestsQueryDto {
  @IsOptional() @IsIn(['chain', 'collection']) scope: 'chain' | 'collection' = 'chain';
  @IsOptional() @IsString() @Length(0, 100) search = '';
}
