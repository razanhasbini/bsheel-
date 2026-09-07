import { Transform } from 'class-transformer';
import { IsIn, IsString, IsUUID, Matches } from 'class-validator';

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
}

export class CollabCodeParam extends JoinCollabGroupDto {}

export class CollabAssignmentParam { @IsUUID() id!: string; }

export class CollabVoteParam {
  @IsUUID() groupId!: string;
  @IsUUID() submissionId!: string;
}
