import { describe, expect, it } from 'vitest';
import {
  businessMemberRoles,
  canManageMembers,
  canReadAnalytics,
  canReadDashboard,
  suggestSlug,
} from '../src/modules/business/domain/business.js';
import { systemRoles } from '../src/common/auth/auth-user.js';

describe('business domain rules', () => {
  /// The decision the whole design rests on. If 'business' ever appears in
  /// systemRoles, RolesGuard starts treating it as a rung on the admin
  /// ladder — an enum whose every existing member means "authority over the
  /// platform" — and the admin dashboard's route gating inherits a role it
  /// has no ordering for.
  it('is not a system role', () => {
    expect(systemRoles).toEqual(['user', 'moderator', 'super_admin']);
    for (const role of businessMemberRoles) {
      expect(systemRoles).not.toContain(role);
    }
  });

  describe('who may manage members', () => {
    it('lets an owner manage them', () => {
      expect(canManageMembers('owner')).toBe(true);
    });

    // A manager that could appoint members could appoint itself an owner,
    // which collapses the two roles into one with extra steps.
    it('refuses a manager', () => {
      expect(canManageMembers('manager')).toBe(false);
    });
  });

  describe('who may read the dashboard', () => {
    it('lets a member of an active business read it', () => {
      expect(canReadDashboard({ businessId: 'b', role: 'manager', status: 'active', analyticsSubscribedAt: null })).toBe(true);
    });

    // Membership alone is never sufficient — suspension has to bite for
    // owners too, or suspending the account that is under dispute does
    // nothing to the person disputing it.
    it('refuses every member of a suspended business, owners included', () => {
      for (const role of businessMemberRoles) {
        expect(canReadDashboard({ businessId: 'b', role, status: 'suspended', analyticsSubscribedAt: null }), role).toBe(false);
      }
    });
  });

  /// #50's whitelist. `status` is a moderation state, not an entitlement;
  /// conflating them gave every business that existed the full dashboard.
  describe('who may read analytics', () => {
    const membership = (
      status: 'active' | 'suspended',
      analyticsSubscribedAt: Date | null,
    ) => ({ businessId: 'b', role: 'owner' as const, status, analyticsSubscribedAt });

    it('lets an active, subscribed business read them', () => {
      expect(canReadAnalytics(membership('active', new Date('2026-09-01')))).toBe(true);
    });

    it('refuses an active business that is not subscribed', () => {
      expect(canReadAnalytics(membership('active', null))).toBe(false);
    });

    // Both conditions, not either: a paid-up business under suspension reads
    // nothing, and neither does an unsuspended one that never subscribed.
    it('refuses a suspended business even while subscribed', () => {
      expect(canReadAnalytics(membership('suspended', new Date('2026-09-01')))).toBe(false);
    });

    it('refuses a suspended, unsubscribed business', () => {
      expect(canReadAnalytics(membership('suspended', null))).toBe(false);
    });

    // The dashboard is one feature. Losing it must not lock a member out of
    // their own account, or the app cannot tell them what they are missing.
    it('does not gate the rest of the business on the subscription', () => {
      expect(canReadDashboard(membership('active', null))).toBe(true);
    });
  });

  describe('slug suggestion', () => {
    it('derives a handle from a display name', () => {
      expect(suggestSlug('Beirut Souks')).toBe('beirut-souks');
    });

    it('folds accents rather than dropping the letters under them', () => {
      // Naive stripping of non-ASCII turns "Café" into "caf", which reads as
      // a typo in a URL the business is about to put on a sign.
      expect(suggestSlug('Café Younes')).toBe('cafe-younes');
    });

    it('collapses punctuation runs and trims the edges', () => {
      expect(suggestSlug('  --Al Falamanki!!  Beirut--  ')).toBe('al-falamanki-beirut');
    });

    it('stays inside the column length limit', () => {
      const slug = suggestSlug('a'.repeat(200));
      expect(slug.length).toBeLessThanOrEqual(64);
    });

    // The column's CHECK demands 3+ chars starting and ending alphanumeric.
    // Returning something unusable would surface as a constraint violation
    // (a 500) instead of the 400 the caller deserves.
    it('returns nothing when a name yields no usable handle', () => {
      for (const name of ['!!!', '   ', '中文名称', 'ab']) {
        expect(suggestSlug(name), name).toBe('');
      }
    });

    it('never suggests a handle the column would reject', () => {
      const pattern = /^[a-z0-9][a-z0-9-]{1,62}[a-z0-9]$/;
      for (const name of ['Beirut Souks', 'Café Younes', '  --Al Falamanki!!  ', 'The 3rd Place']) {
        const slug = suggestSlug(name);
        if (slug) expect(slug, name).toMatch(pattern);
      }
    });
  });
});
