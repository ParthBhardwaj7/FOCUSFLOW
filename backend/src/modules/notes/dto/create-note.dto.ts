import { IsBoolean, IsOptional, IsString, MaxLength } from 'class-validator';

export class CreateNoteDto {
  @IsOptional()
  @IsString()
  @MaxLength(200)
  title?: string;

  @IsOptional()
  @IsString()
  @MaxLength(50_000)
  body?: string;

  @IsOptional()
  @IsBoolean()
  pinned?: boolean;
}
