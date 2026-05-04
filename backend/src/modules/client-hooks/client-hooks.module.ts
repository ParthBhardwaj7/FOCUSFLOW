import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module';
import { PrismaModule } from '../../prisma/prisma.module';
import { MobileRuntimeService } from './mobile-runtime.service';
import { PublicConfigController } from './public-config.controller';
import { ErrorReportController } from './error-report.controller';
import { MobileFlagsController } from './mobile-flags.controller';
import { MobileAiSuggestionsController } from './mobile-ai-suggestions.controller';
import { MobilePushController } from './mobile-push.controller';

@Module({
  imports: [PrismaModule, AuthModule],
  controllers: [
    PublicConfigController,
    ErrorReportController,
    MobileFlagsController,
    MobileAiSuggestionsController,
    MobilePushController,
  ],
  providers: [MobileRuntimeService],
  exports: [MobileRuntimeService],
})
export class ClientHooksModule {}
