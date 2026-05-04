import {
  IsArray,
  IsBoolean,
  IsInt,
  IsOptional,
  IsString,
  Max,
  Min,
  MinLength,
} from 'class-validator';

export class AdminCreateFlagDto {
  @IsString()
  @MinLength(2)
  key!: string;

  @IsOptional()
  @IsBoolean()
  isEnabled?: boolean;

  @IsOptional()
  @IsInt()
  @Min(0)
  @Max(100)
  rolloutPercentage?: number;

  @IsOptional()
  @IsArray()
  @IsString({ each: true })
  enabledForUserIds?: string[];

  @IsOptional()
  @IsString()
  description?: string;
}
