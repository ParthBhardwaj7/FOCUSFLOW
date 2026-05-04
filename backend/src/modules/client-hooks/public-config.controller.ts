import { Controller, Get } from '@nestjs/common';
import { Throttle } from '@nestjs/throttler';
import { Public } from '../../common/decorators/public.decorator';
import { MobileRuntimeService } from './mobile-runtime.service';

@Public()
@Throttle({ default: { limit: 120, ttl: 60_000 } })
@Controller({ path: 'config', version: '1' })
export class PublicConfigController {
  constructor(private readonly mobile: MobileRuntimeService) {}

  @Get('public')
  publicConfig() {
    return this.mobile.publicConfig();
  }
}
