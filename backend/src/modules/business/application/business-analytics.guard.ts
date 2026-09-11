import {
  ForbiddenException,
  Injectable,
  type CanActivate,
  type ExecutionContext,
} from '@nestjs/common';
import { canReadAnalytics } from '../domain/business.js';
import type { RequestWithBusiness } from './business-access.guard.js';

/// The analytics entitlement — #50's "dynamic whitelist ... every business
/// subscribed with bsheel analytics".
///
/// Why this is a second guard rather than a branch inside
/// `BusinessAccessGuard`: membership and entitlement authorise different
/// things. Membership decides whether you may see *this business at all*,
/// and it governs every business route. Entitlement decides whether this
/// business has bought *one feature*, and it governs only the analytics
/// routes — a member must still be able to read `/businesses/me` and see
/// their own account when they are not subscribed, or the app cannot even
/// tell them what they are missing.
///
/// It runs after `BusinessAccessGuard` (declared second in `@UseGuards`,
/// which is the order Nest applies) and reads the membership that guard
/// already resolved, so the entitlement costs no extra query.
///
/// 403 and not 404 here, deliberately — the opposite of the non-member
/// case. A member knows the business exists; they are one of its people.
/// Hiding the reason would leave an owner staring at an empty dashboard
/// with no way to discover that the fix is a subscription.
@Injectable()
export class BusinessAnalyticsGuard implements CanActivate {
  canActivate(context: ExecutionContext): boolean {
    const request = context.switchToHttp().getRequest<RequestWithBusiness>();
    const membership = request.business;

    // Absent only if this guard were ever mounted without BusinessAccessGuard
    // ahead of it. Failing closed rather than assuming, because the failure
    // mode of guessing here is serving analytics to someone unauthorised.
    if (!membership) {
      throw new ForbiddenException({
        code: 'INSUFFICIENT_PERMISSION',
        message: 'You do not have permission to perform this action',
      });
    }
    if (!canReadAnalytics(membership)) {
      throw new ForbiddenException({
        code: 'ANALYTICS_NOT_SUBSCRIBED',
        message: 'This business is not subscribed to Bsheel analytics',
      });
    }
    return true;
  }
}
