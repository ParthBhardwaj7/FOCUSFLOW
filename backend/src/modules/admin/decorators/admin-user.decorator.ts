import { createParamDecorator, ExecutionContext } from '@nestjs/common';
import type { Request } from 'express';

export type AdminRequestUser = {
  userId: string;
  email: string;
  role: import('@prisma/client').UserRole;
};

export const AdminUser = createParamDecorator(
  (_data: unknown, ctx: ExecutionContext): AdminRequestUser => {
    const req = ctx
      .switchToHttp()
      .getRequest<Request & { user: AdminRequestUser }>();
    return req.user;
  },
);
