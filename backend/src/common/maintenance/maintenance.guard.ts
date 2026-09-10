import {
  Injectable,
  ServiceUnavailableException,
  type CanActivate,
  type ExecutionContext,
} from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import type { Request, Response } from 'express';
import type { AuthUser, SystemRole } from '../auth/auth-user.js';
import { IS_PUBLIC_KEY } from '../auth/public.decorator.js';
import { ALLOW_DURING_MAINTENANCE_KEY } from './allow-during-maintenance.decorator.js';
import { MaintenanceModeService } from '../../modules/admin/application/maintenance-mode.service.js';
import {
  maintenanceErrorCode,
  maintenanceErrorMessage,
  maintenanceRetryAfterSeconds,
  rolesExemptFromMaintenance,
} from '../../modules/admin/domain/maintenance.js';

/**
 * Refuses ordinary traffic while maintenance mode is on.
 *
 * Authentication has already established who is calling by the time this runs;
 * this guard decides whether that caller may use the API *right now*, which is
 * an authorisation question and belongs here rather than in the auth layer.
 * It is registered last of the global guards in `AppModule` for exactly that
 * reason — the order is load-bearing, because without `request.user` the
 * admin exemption below cannot be evaluated and an operator would lock
 * themselves out of the switch they need to flip back.
 *
 * Three things stay reachable, and each one is a lockout waiting to happen if
 * it does not:
 *
 * 1. **Anything reachable without a session.** That is `/health/live` and
 *    `/health/ready` (block those and the orchestrator kills the container as
 *    unhealthy, turning a maintenance window into a real outage),
 *    `GET /config` (the only way a client learns maintenance is on — block it
 *    and the app shows generic failures instead of the maintenance screen,
 *    and the console cannot read the flag to turn it off), the `/auth/*`
 *    endpoints (identity has to be established before a role can be checked,
 *    so blocking sign-in locks the operator out of the console that holds the
 *    off switch), the public compliance intake, and the Telegram webhook.
 *    None of those is user traffic in the sense that matters; refusing them
 *    costs the operator their way back in and buys nothing.
 * 2. **Admins.** `moderator` and `super_admin` keep full access, which is what
 *    makes the mode recoverable and lets moderation continue during a window.
 * 3. **Routes marked `@AllowDuringMaintenance()`**, for an authenticated route
 *    that must survive a window. Nothing needs it today.
 *
 * Everything else gets `503` with `SERVICE_UNDER_MAINTENANCE` and a
 * `Retry-After`, so a client can tell "closed on purpose" from "broken".
 */
@Injectable()
export class MaintenanceGuard implements CanActivate {
  constructor(
    private readonly reflector: Reflector,
    private readonly maintenance: MaintenanceModeService,
  ) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    if (context.getType() !== 'http') return true;

    const request = context
      .switchToHttp()
      .getRequest<Request & { user?: AuthUser }>();

    // Cheap, allocation-free exits before the (cached) flag read, so a
    // health probe never depends on the database being answerable.
    if (this.hasMetadata(context, IS_PUBLIC_KEY)) return true;
    if (this.hasMetadata(context, ALLOW_DURING_MAINTENANCE_KEY)) return true;
    if (request.user && isExemptRole(request.user.role)) return true;

    if (!(await this.maintenance.isEnabled())) return true;

    context
      .switchToHttp()
      .getResponse<Response>()
      .setHeader('Retry-After', String(maintenanceRetryAfterSeconds));
    throw new ServiceUnavailableException({
      code: maintenanceErrorCode,
      message: maintenanceErrorMessage,
    });
  }

  private hasMetadata(context: ExecutionContext, key: string): boolean {
    return (
      this.reflector.getAllAndOverride<boolean>(key, [
        context.getHandler(),
        context.getClass(),
      ]) === true
    );
  }
}

const exemptRoles: ReadonlySet<string> = new Set(rolesExemptFromMaintenance);

function isExemptRole(role: SystemRole): boolean {
  return exemptRoles.has(role);
}
