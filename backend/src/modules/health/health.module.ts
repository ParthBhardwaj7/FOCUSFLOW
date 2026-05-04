import { Module } from '@nestjs/common';
import {
  HealthController,
  HealthSummaryController,
  ReadyController,
} from './health.controller';
import { HealthService } from './health.service';

@Module({
  controllers: [HealthSummaryController, HealthController, ReadyController],
  providers: [HealthService],
})
export class HealthModule {}
