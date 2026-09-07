import { Type } from 'class-transformer';
import { ArrayMaxSize, ArrayMinSize, Equals, IsArray, IsBoolean, IsIn, IsInt, IsOptional, IsString, IsUUID, Length, Max, Min, ValidateNested } from 'class-validator';

export class QuestIdDto {
  @IsUUID()
  questId!: string;
}

export class UserQuestIdDto {
  @IsUUID()
  userQuestId!: string;
}

export class QuestPickerQueryDto {
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(20)
  count = 3;
}

export class FollowingActiveQueryDto {
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(40)
  limit = 12;
}

export class QuestHistoryQueryDto {
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(100)
  limit = 50;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(0)
  offset = 0;
}

export class CreateQuestDto {
  @IsString()
  @Length(1, 160)
  title!: string;

  @IsString()
  @Length(1, 2000)
  description!: string;

  @IsString()
  @Length(1, 80)
  category!: string;

  @IsIn(['easy', 'medium', 'hard'])
  difficulty!: string;

  @IsInt()
  @Min(0)
  @Max(10_000)
  xpReward!: number;

  @IsInt()
  @Min(1)
  @Max(168)
  durationHours = 4;

  @IsBoolean()
  isActive = true;
}

export class UpdateQuestDto {
  @IsOptional()
  @IsString()
  @Length(1, 160)
  title?: string;

  @IsOptional()
  @IsString()
  @Length(1, 2000)
  description?: string;

  @IsOptional()
  @IsString()
  @Length(1, 80)
  category?: string;

  @IsOptional()
  @IsIn(['easy', 'medium', 'hard'])
  difficulty?: string;

  @IsOptional()
  @IsInt()
  @Min(0)
  @Max(10_000)
  xpReward?: number;

  @IsOptional()
  @IsInt()
  @Min(1)
  @Max(168)
  durationHours?: number;

  @IsOptional()
  @IsBoolean()
  isActive?: boolean;
}

export class BulkCreateQuestsDto {
  @IsArray()
  @ArrayMinSize(1)
  @ArrayMaxSize(1000)
  @ValidateNested({ each: true })
  @Type(() => CreateQuestDto)
  quests!: CreateQuestDto[];
}

export class DeleteAllQuestsDto {
  @Equals('DELETE ALL')
  confirmation!: 'DELETE ALL';
}
