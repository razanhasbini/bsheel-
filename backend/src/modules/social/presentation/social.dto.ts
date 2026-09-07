import { IsIn, IsOptional, IsString, IsUUID, Length, MaxLength } from 'class-validator';

export class VoteDto {
  @IsIn(['upvote', 'downvote']) type!: 'upvote' | 'downvote';
}

export class AddCommentDto {
  @IsString() @Length(1, 2000) body!: string;
  @IsOptional() @IsUUID() parentId?: string;
}

export class BlockUserDto {
  @IsOptional() @IsString() @MaxLength(500) reason = 'Blocked by user';
}

export class ReportContentDto {
  @IsIn(['submission', 'comment', 'user']) reportedType!: 'submission' | 'comment' | 'user';
  @IsString() @Length(1, 200) reportedId!: string;
  @IsString() @Length(1, 500) reason!: string;
}

