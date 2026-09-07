import { Transform, Type } from 'class-transformer';
import { ArrayMaxSize, IsArray, IsIn, IsInt, IsString, IsUUID, Length, Matches, Max, Min } from 'class-validator';

export class CreateUploadIntentDto {
  @IsUUID()
  clientRequestId!: string;

  @IsIn(['avatar', 'submission'])
  kind!: 'avatar' | 'submission';

  @Transform(({ value }) => typeof value === 'string' ? value.toLowerCase().trim() : value)
  @IsIn(['image/jpeg', 'image/png', 'image/gif', 'image/webp', 'video/mp4', 'video/quicktime', 'video/webm'])
  contentType!: string;

  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(50 * 1024 * 1024)
  sizeBytes!: number;
}

export class CompleteUploadDto {
  @IsUUID()
  objectId!: string;
}

export class SignMediaDto {
  @IsArray()
  @ArrayMaxSize(100)
  @IsString({ each: true })
  @Length(1, 2000, { each: true })
  urls!: string[];
}

export class DeleteMediaObjectDto {
  @IsString()
  @Matches(/^(avatars|submissions)\/[0-9a-f-]{36}\/[A-Za-z0-9._-]+$/i)
  key!: string;
}
