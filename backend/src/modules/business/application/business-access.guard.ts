import {
  ForbiddenException,
  Injectable,
  NotFoundException,
  SetMetadata,
  type CanActivate,
  type ExecutionContext,
} from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import type { Request } from 'express';
import type { AuthUser } from '../../../common/auth/auth-user.js';
import { canManageMembers, canReadDashboard, type BusinessMembership } from '../domain/business.js';
import { BusinessRepository } from '../infrastructure/business.repository.js';

export const BUSINESS_OWNER_KEY = 'business:requiresOwner';

/// Marks a route as owner-only within its business. Without it a route
/// requires membership alone.
export const BusinessOwner = () => SetMetadata(BUSINESS_OWNER_KEY, true);

export interface RequestWithBusiness extends Request {
  user?: AuthUser;
  business?: BusinessMembership;
}

/// Authorises a request against one business, by membership.
///
/// This is the whole security boundary for #14 and #50: everything a
/// business can read is scoped to the places it owns, and this is where
/// "it owns them" is established. Three properties it has to hold:
///
/// 1. **Membership is read from the database on every request**, never from
///    the access token. Access is granted and revoked by an admin, and a
///    token issued before a revocation would otherwise keep working until
///    it expired — a removed employee reading a dashboard for another hour.
///
/// 2. **A non-member gets 404, not 403.** 403 confirms the business exists,
///    which turns id enumeration into a directory of who is on the platform.
///    A caller with no membership is told the same thing whether the id is
///    real or invented.
///
/// 3. **Suspension is checked here**, so a suspended business stops
///    answering at the boundary rather than in each handler that might
///    forget.
@Injectable()
export class BusinessAccessGuard implements CanActivate {
  constructor(
    private readonly businesses: BusinessRepository,
    private readonly reflector: Reflector,
  ) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const request = context.switchToHttp().getRequest<RequestWithBusiness>();
    const user = request.user;
    if (!user) {
      throw new ForbiddenException({
        code: 'INSUFFICIENT_PERMISSION',
        message: 'You do not have permission to perform this action',
      });
    }

    const businessId = request.params?.businessId;
    // Routes carrying no :businessId are not this guard's business; the
    // controller resolves the caller's own memberships instead.
    if (typeof businessId !== 'string' || businessId.length === 0) return true;

    const membership = await this.businesses.membership(user.id, businessId);
    // Not a member: indistinguishable from "no such business", deliberately.
    if (!membership) {
      throw new NotFoundException({ code: 'BUSINESS_NOT_FOUND', message: 'Business not found' });
    }
    if (!canReadDashboard(membership)) {
      throw new ForbiddenException({
        code: 'BUSINESS_SUSPENDED',
        message: 'This business account is suspended',
      });
    }

    const ownerOnly = this.reflector.getAllAndOverride<boolean>(BUSINESS_OWNER_KEY, [
      context.getHandler(),
      context.getClass(),
    ]);
    if (ownerOnly && !canManageMembers(membership.role)) {
      throw new ForbiddenException({
        code: 'BUSINESS_OWNER_REQUIRED',
        message: 'Only a business owner can perform this action',
      });
    }

    // Handlers read the resolved membership rather than looking it up again.
    request.business = membership;
    return true;
  }
}
