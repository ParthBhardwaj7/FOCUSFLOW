import { SetMetadata } from '@nestjs/common';
import type { UserRole } from '@prisma/client';

export const ADMIN_ROLES_KEY = 'adminRoles';

export const AdminRoles = (...roles: UserRole[]) =>
  SetMetadata(ADMIN_ROLES_KEY, roles);
