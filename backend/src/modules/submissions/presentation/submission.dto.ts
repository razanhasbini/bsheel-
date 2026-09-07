import { IsBoolean, IsIn, IsOptional, IsString, IsUUID, Length, MaxLength } from 'class-validator';

export class CreateSubmissionDto {
  @IsUUID()
  userQuestId!: string;

  @IsString()
  @Length(1, 20_000)
  mediaUrl!: string;

  @IsIn(['image', 'video', 'mixed'])
  mediaType!: 'image' | 'video' | 'mixed';

  @IsOptional()
  @IsString()
  @MaxLength(2200)
  caption?: string;

  @IsBoolean()
  showInFeed = true;
}

export class AppealSubmissionDto {
  @IsString()
  @Length(3, 2000)
  appealNote!: string;
}

export class ReviewSubmissionDto {
  @IsOptional()
  @IsString()
  @MaxLength(2000)
  reviewNote?: string;
}

export class RejectSubmissionDto {
  @IsString()
  @Length(1, 2000)
  reviewNote!: string;
}

export class SetVisibilityDto {
  @IsIn(['visible', 'hidden_from_feed', 'deleted'])
  visibility!: 'visible' | 'hidden_from_feed' | 'deleted';
}
