import { IsOptional, IsString, MaxLength } from 'class-validator';

export class CreateVoiceNoteDto {
  @IsOptional()
  @IsString()
  @MaxLength(200)
  title?: string;

  /** Optional speech-to-text transcript (plain text). */
  @IsOptional()
  @IsString()
  @MaxLength(20_000)
  transcript?: string;

  @IsOptional()
  @IsString()
  @MaxLength(500)
  tags?: string;
}
