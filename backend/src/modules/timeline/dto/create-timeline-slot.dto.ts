import {
  IsDateString,
  IsEnum,
  IsInt,
  IsOptional,
  IsString,
  MaxLength,
  Min,
  MinLength,
} from 'class-validator';
import { TimelineSlotStatus } from '@prisma/client';

export class CreateTimelineSlotDto {
  @IsDateString()
  startsAt!: string;

  @IsDateString()
  endsAt!: string;

  @IsString()
  @MinLength(1)
  @MaxLength(500)
  title!: string;

  @IsOptional()
  @IsString()
  @MaxLength(32)
  iconKey?: string;

  @IsOptional()
  @IsString()
  @MaxLength(64)
  tag?: string;

  @IsOptional()
  @IsString()
  @MaxLength(128)
  soundLabel?: string;

  @IsOptional()
  @IsEnum(TimelineSlotStatus)
  status?: TimelineSlotStatus;

  @IsOptional()
  @IsString()
  linkedTaskId?: string;

  @IsOptional()
  @IsInt()
  @Min(0)
  sortOrder?: number;
}
