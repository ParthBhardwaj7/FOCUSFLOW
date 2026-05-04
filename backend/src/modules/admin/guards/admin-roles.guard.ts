import {
  CanActivate,
  ExecutionContext,
  ForbiddenException,
  Injectable,
} from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { UserRole } from '@prisma/client';
import { ADMIN_ROLES_KEY } from '../decorators/admin-roles.decorator';
import type { AdminRequestUser } from '../decorators/admin-user.decorator';

@Injectable()
export class AdminRolesGuard implements CanActivate {
  constructor(private readonly reflector: Reflector) {}

  canActivate(context: ExecutionContext): boolean {
    const required = this.reflector.getAllAndOverride<UserRole[]>(
      ADMIN_ROLES_KEY,
      [context.getHandler(), context.getClass()],
    ) ?? [UserRole.ADMIN, UserRole.SUPERADMIN];
    const req = context.switchToHttp().getRequest<{ user: AdminRequestUser }>();
    const user = req.user;
    if (!user) {
      throw new ForbiddenException();
    }
    if (!required.includes(user.role)) {
      throw new ForbiddenException();
    }
    return true;
  }
}
