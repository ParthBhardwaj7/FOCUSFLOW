import { Controller, Get } from '@nestjs/common';
import { Throttle } from '@nestjs/throttler';
import { CurrentUser } from '../../common/decorators/current-user.decorator';
import type { JwtUserPayload } from '../../common/decorators/current-user.decorator';
import { MobileRuntimeService } from './mobile-runtime.service';

@Throttle({ default: { limit: 40, ttl: 60_000 } })
@Controller({ path: 'ai-suggestions', version: '1' })
export class MobileAiSuggestionsController {
  constructor(private readonly mobile: MobileRuntimeService) {}

  @Get()
  suggestions(@CurrentUser() u: JwtUserPayload) {
    return this.mobile.matchingAiSuggestions(u.userId);
  }
}
