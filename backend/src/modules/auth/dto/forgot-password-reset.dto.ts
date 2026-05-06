import { IsEmail, IsString, Matches, MinLength } from 'class-validator';

export class ForgotPasswordResetDto {
  @IsEmail()
  email!: string;

  @IsString()
  @Matches(/^\d{6}$/, { message: 'Code must be exactly 6 digits' })
  code!: string;

  @IsString()
  @MinLength(8, { message: 'Password must be at least 8 characters' })
  newPassword!: string;
}
