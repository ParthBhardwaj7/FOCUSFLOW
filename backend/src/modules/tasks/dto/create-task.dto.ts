import {
  IsBoolean,
  IsInt,
  IsOptional,
  IsString,
  Matches,
  MaxLength,
  Min,
  MinLength,
} from 'class-validator';

export class CreateTaskDto {
  @IsString()
  @MinLength(1)
  @MaxLength(500)
  title!: string;

  @IsOptional()
  @IsString()
  @MaxLength(10_000)
  notes?: string;

  /** Calendar date `YYYY-MM-DD` (interpreted as UTC midnight for MVP). */
  @Matches(/^\d{4}-\d{2}-\d{2}$/)
  scheduledOn!: string;

  @IsOptional()
  @IsInt()
  @Min(0)
  sortOrder?: number;

  @IsOptional()
  @IsBoolean()
  isMit?: boolean;
}
