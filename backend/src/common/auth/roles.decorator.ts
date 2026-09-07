import { SetMetadata } from '@nestjs/common';
import type { SystemRole } from './auth-user.js';

export const ROLES_KEY = 'roles';
export const Roles = (...roles: readonly SystemRole[]) => SetMetadata(ROLES_KEY, roles);

