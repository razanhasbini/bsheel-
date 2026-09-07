import { Transform } from 'class-transformer';
import { IsEmail, IsIn, IsOptional, IsString, Length, MaxLength } from 'class-validator';

export class JoinWaitlistDto {
  @Transform(({ value }) => typeof value === 'string' ? value.trim().toLowerCase() : value)
  @IsEmail()
  @MaxLength(254)
  email!: string;

  @IsOptional() @IsString() @MaxLength(40) source?: string;
}

export class SubmitQuestSuggestionDto {
  @IsString() @Length(3, 100) title!: string;
  @IsString() @Length(10, 500) description!: string;
  @IsIn(['fitness', 'creativity', 'social', 'learning', 'adventure']) category!: string;
  @IsIn(['easy', 'medium', 'hard']) difficulty!: string;
  @IsOptional() @IsString() @MaxLength(60) suggestedByName?: string;
  @IsOptional() @IsString() @MaxLength(40) suggestedByHandle?: string;
}
