import {
  IsBoolean,
  IsDateString,
  IsOptional,
  IsString,
  MaxLength,
} from 'class-validator';

export class PatchNoteDto {
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

  /** If sent, must match current row `updatedAt` or API returns 409. */
  @IsOptional()
  @IsDateString()
  expectedUpdatedAt?: string;
}
