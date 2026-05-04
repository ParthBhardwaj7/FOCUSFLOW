import { IsOptional, IsString, MaxLength } from 'class-validator';

export class ErrorReportDto {
  @IsString()
  @MaxLength(200)
  errorType!: string;

  @IsString()
  @MaxLength(8000)
  message!: string;

  @IsOptional()
  @IsString()
  @MaxLength(200)
  screen?: string;

  @IsOptional()
  @IsString()
  @MaxLength(100)
  appVersion?: string;

  @IsOptional()
  @IsString()
  @MaxLength(100)
  deviceOs?: string;

  /** Friendly text already shown (or intended) for the end user — stored for admin triage. */
  @IsOptional()
  @IsString()
  @MaxLength(500)
  surfaceMessage?: string;
}
