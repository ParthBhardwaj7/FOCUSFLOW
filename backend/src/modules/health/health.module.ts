import { Module } from '@nestjs/common';
import { HealthController, ReadyController } from './health.controller';
import { HealthService } from './health.service';

@Module({
  controllers: [HealthController, ReadyController],
  providers: [HealthService],
})
export class HealthModule {}
