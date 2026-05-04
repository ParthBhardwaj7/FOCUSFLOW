import { IsOptional, IsString, MaxLength } from 'class-validator';

export class AdminBanUserDto {
  @IsString()
  @MaxLength(2000)
  reason!: string;

  @IsOptional()
  banExpiresAt?: string;
}
