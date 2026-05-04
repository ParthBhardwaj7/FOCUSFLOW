import {
  IsArray,
  IsBoolean,
  IsInt,
  IsOptional,
  IsString,
  Max,
  Min,
} from 'class-validator';

export class AdminUpdateFlagDto {
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

  @IsOptional()
  scheduledEnableAt?: string;

  @IsOptional()
  scheduledDisableAt?: string;
}
