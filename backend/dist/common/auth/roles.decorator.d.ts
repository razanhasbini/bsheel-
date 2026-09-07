import type { SystemRole } from './auth-user.js';
export declare const ROLES_KEY = "roles";
export declare const Roles: (...roles: readonly SystemRole[]) => import("@nestjs/common").CustomDecorator<string>;
