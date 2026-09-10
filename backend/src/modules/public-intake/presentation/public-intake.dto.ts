import { Transform } from 'class-transformer';
import { Equals, IsEmail, IsIn, IsOptional, IsString, Length, MaxLength } from 'class-validator';

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

/**
 * A deletion request from the public, unauthenticated page.
 *
 * `confirmation` mirrors the authenticated flow's typed confirmation so the
 * button cannot be triggered by a stray submit, and the response says nothing
 * about whether the address has an account — an unauthenticated endpoint that
 * confirmed account existence would be an enumeration oracle.
 */
export class RequestAccountDeletionDto {
  @Transform(({ value }) => typeof value === 'string' ? value.trim().toLowerCase() : value)
  @IsEmail()
  @MaxLength(254)
  email!: string;

  @IsOptional() @IsString() @MaxLength(2000) note?: string;

  @Equals('DELETE')
  confirmation!: string;
}
