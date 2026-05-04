import { IsString, MinLength } from 'class-validator';

export class AdminRefreshDto {
  @IsString()
  @MinLength(10)
  refreshToken!: string;
}
