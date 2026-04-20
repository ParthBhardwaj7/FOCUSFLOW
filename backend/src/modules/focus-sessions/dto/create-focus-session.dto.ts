import {
  IsInt,
  IsObject,
  IsOptional,
  IsString,
  Max,
  Min,
} from 'class-validator';

export class CreateFocusSessionDto {
  @IsOptional()
  @IsString()
  taskId?: string;

  @IsInt()
  @Min(1)
  @Max(86400)
  plannedDurationSec!: number;

  @IsOptional()
  @IsObject()
  subtasksSnapshot?: Record<string, unknown>;
}
