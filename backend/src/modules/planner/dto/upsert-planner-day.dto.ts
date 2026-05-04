import { ArrayMaxSize, IsArray } from 'class-validator';

/** Raw slot objects as stored by the mobile planner (same shape as local JSON). */
export class UpsertPlannerDayDto {
  @IsArray()
  @ArrayMaxSize(400)
  slots!: unknown[];
}
