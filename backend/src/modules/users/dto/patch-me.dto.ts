import { IsDateString, IsOptional, IsString, MaxLength } from 'class-validator';

export class PatchMeDto {
  @IsOptional()
  @IsDateString()
  onboardingCompletedAt?: string;

  @IsOptional()
  @IsString()
  @MaxLength(64)
  timeZone?: string;

  @IsOptional()
  @IsString()
  @MaxLength(20_000)
  profileSummary?: string;
}
