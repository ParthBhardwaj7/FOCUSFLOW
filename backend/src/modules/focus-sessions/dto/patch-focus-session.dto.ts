import { IsIn } from 'class-validator';

/** Ending a session must be terminal (not PENDING). */
export class PatchFocusSessionDto {
  @IsIn(['COMPLETED', 'SKIPPED'])
  outcome!: 'COMPLETED' | 'SKIPPED';
}
