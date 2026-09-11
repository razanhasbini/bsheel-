/// Business / destination accounts (#14).
///
/// The thing to hold onto: a business is an *ordinary player* with extra
/// rights over its own places. It is not an admin, not a tier of user, and
/// not a variant account. Its member logs in as themselves, rolls quests,
/// posts to the feed and appears on the leaderboard exactly like anyone
/// else — and additionally may read the dashboard for the places it speaks
/// for.
///
/// That is why nothing here touches SystemRole. See the header of
/// migration 0038 for why membership rather than rank.

export const businessStatuses = ['active', 'suspended'] as const;
export type BusinessStatus = (typeof businessStatuses)[number];

/// Scoped to one business. There is no global business role: being an owner
/// of one business says nothing about any other.
export const businessMemberRoles = ['owner', 'manager'] as const;
export type BusinessMemberRole = (typeof businessMemberRoles)[number];

export interface Business {
  readonly id: string;
  readonly name: string;
  readonly slug: string;
  readonly description: string;
  readonly contactEmail: string | null;
  readonly websiteUrl: string | null;
  readonly logoUrl: string | null;
  readonly status: BusinessStatus;
  readonly createdAt: Date;
}

export interface BusinessPlace {
  readonly placeId: string;
  readonly name: string;
  readonly city: string;
  readonly countryCode: string;
  readonly category: string;
  readonly isPublished: boolean;
  readonly linkedAt: Date;
}

/// What the caller may do, resolved per request rather than read off the
/// access token. A token outlives a revocation; this does not.
export interface BusinessMembership {
  readonly businessId: string;
  readonly role: BusinessMemberRole;
  readonly status: BusinessStatus;
}

/// A member's view of a business they belong to.
export interface BusinessSummary extends Business {
  readonly membershipRole: BusinessMemberRole;
  readonly places: readonly BusinessPlace[];
}

/// Only an owner may change who else can see the dashboard. A manager that
/// could appoint members could appoint itself an owner, which makes the two
/// roles the same role with extra steps.
export const canManageMembers = (role: BusinessMemberRole): boolean => role === 'owner';

/// A suspended business keeps its place links — losing them would destroy
/// the record of what was claimed, which is exactly what a dispute needs —
/// but reads nothing. Membership alone is never sufficient.
export const canReadDashboard = (membership: BusinessMembership): boolean =>
  membership.status === 'active';

/// Derives a URL-safe handle from a display name.
///
/// Deliberately lossy and deliberately not unique: it is a *suggestion* the
/// caller may override, and the database's UNIQUE constraint is what
/// actually decides. Generating "the next free slug" here would be a
/// check-then-write race between two admins creating similarly named
/// businesses at once.
export function suggestSlug(name: string): string {
  const slug = name
    .normalize('NFKD')
    // Strip combining marks, so "Café" and "Cafe" suggest the same handle
    // rather than one of them collapsing to "caf".
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 64)
    .replace(/-+$/g, '');
  // The column's CHECK requires at least three characters starting and
  // ending alphanumeric. A name of only punctuation or non-Latin script
  // leaves nothing usable, and an empty string would fail that constraint
  // as a confusing 500 rather than a validation error.
  return slug.length >= 3 ? slug : '';
}
