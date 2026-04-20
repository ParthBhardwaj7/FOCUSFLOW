import { createParamDecorator, ExecutionContext } from '@nestjs/common';
import type { Request } from 'express';

export type JwtUserPayload = {
  userId: string;
  email: string;
};

export const CurrentUser = createParamDecorator(
  (_data: unknown, ctx: ExecutionContext): JwtUserPayload => {
    const req = ctx
      .switchToHttp()
      .getRequest<Request & { user: JwtUserPayload }>();
    return req.user;
  },
);
