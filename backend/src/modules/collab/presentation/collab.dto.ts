import { Transform } from 'class-transformer';
import { IsBoolean, IsIn, IsOptional, IsString, IsUUID, Matches } from 'class-validator';

export class CreateCollabGroupDto {
  @IsUUID()
  userQuestId!: string;

  @IsIn(['with', 'versus'])
  mode: 'with' | 'versus' = 'with';
}

export class JoinCollabGroupDto {
  @Transform(({ value }) => typeof value === 'string' ? value.trim().toUpperCase() : value)
  @IsString()
  @Matches(/^[A-F0-9]{6}$/)
  code!: string;

  /**
   * Give up the caller's in-progress quest to take this group's quest.
   *
   * The client used to do this in two calls: abandon, then join. When the
   * join then failed — a full group, a block, an expired code, a dropped
   * connection — the quest was already gone and the user was in no group,
   * with nothing to roll again until the reroll window allowed it. Sending
   * the intent lets the server do both inside the join transaction, so
   * either the swap happens or nothing does.
   *
   * Defaults to false, which keeps the old refusal (`ACTIVE_QUEST_EXISTS`)
   * for a caller that has not asked for the swap — including the build
   * already in TestFlight, which sends no such field.
   */
  @IsOptional()
  @IsBoolean()
  abandonActiveQuest = false;
}

/** Only the code — a preview must not carry the join intent. */
export class CollabCodeParam {
  @Transform(({ value }) => typeof value === 'string' ? value.trim().toUpperCase() : value)
  @IsString()
  @Matches(/^[A-F0-9]{6}$/)
  code!: string;
}

export class CollabAssignmentParam { @IsUUID() id!: string; }

export class CollabGroupParam { @IsUUID() groupId!: string; }

export class CollabVoteParam {
  @IsUUID() groupId!: string;
  @IsUUID() submissionId!: string;
}
