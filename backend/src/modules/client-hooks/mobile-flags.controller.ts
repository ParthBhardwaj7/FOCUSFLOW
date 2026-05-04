import { Controller, Get } from '@nestjs/common';
import { Throttle } from '@nestjs/throttler';
import { CurrentUser } from '../../common/decorators/current-user.decorator';
import type { JwtUserPayload } from '../../common/decorators/current-user.decorator';
import { MobileRuntimeService } from './mobile-runtime.service';

@Throttle({ default: { limit: 60, ttl: 60_000 } })
@Controller({ path: 'flags', version: '1' })
export class MobileFlagsController {
  constructor(private readonly mobile: MobileRuntimeService) {}

  @Get()
  flags(@CurrentUser() u: JwtUserPayload) {
    return this.mobile.evaluateFlags(u.userId);
  }
}
