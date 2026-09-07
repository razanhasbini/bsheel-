import { Type } from 'class-transformer';
import { IsIn, IsInt, IsOptional, Max, Min } from 'class-validator';

export class FeedQueryDto {
  @IsOptional() @Type(() => Number) @IsInt() @Min(1) @Max(50) limit = 20;
  @IsOptional() @Type(() => Number) @IsInt() @Min(0) offset = 0;
  @IsOptional() @IsIn(['recent', 'top', 'hot', 'bottom', 'graveyard']) sort = 'recent';
  @IsOptional() @IsIn(['all', 'following']) scope: 'all' | 'following' = 'all';
}

