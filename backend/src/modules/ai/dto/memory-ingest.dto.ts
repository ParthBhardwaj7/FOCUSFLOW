import { MemorySource } from '@prisma/client';
import { IsEnum, IsOptional, IsString, MaxLength } from 'class-validator';

export class MemoryIngestDto {
  @IsString()
  @MaxLength(4000)
  content!: string;

  @IsOptional()
  @IsEnum(MemorySource)
  source?: MemorySource;
}
