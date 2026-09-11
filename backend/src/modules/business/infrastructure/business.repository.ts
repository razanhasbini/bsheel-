import { Injectable } from '@nestjs/common';
import { DatabaseService } from '../../../infrastructure/database/database.service.js';
import type {
  Business,
  BusinessMemberRole,
  BusinessMembership,
  BusinessPlace,
  BusinessStatus,
  BusinessSummary,
} from '../domain/business.js';

interface BusinessRow {
  readonly id: string;
  readonly name: string;
  readonly slug: string;
  readonly description: string;
  readonly contact_email: string | null;
  readonly website_url: string | null;
  readonly logo_url: string | null;
  readonly status: BusinessStatus;
  readonly analytics_subscribed_at: Date | null;
  readonly created_at: Date;
}

const toBusiness = (row: BusinessRow): Business => ({
  id: row.id,
  name: row.name,
  slug: row.slug,
  description: row.description,
  contactEmail: row.contact_email,
  websiteUrl: row.website_url,
  logoUrl: row.logo_url,
  status: row.status,
  analyticsSubscribedAt: row.analytics_subscribed_at,
  createdAt: row.created_at,
});

// citext columns come back as their own type through pg's parser, so both
// are cast to text for a plain string in the row.
const BUSINESS_COLUMNS = `id, name, slug::text AS slug, description,
  contact_email::text AS contact_email, website_url, logo_url, status,
  analytics_subscribed_at, created_at`;

/// The same columns qualified for a join. Written out rather than derived
/// from the string above: a split-and-prefix would silently produce
/// nonsense the day someone adds a column containing a comma.
const JOINED_BUSINESS_COLUMNS = `b.id, b.name, b.slug::text AS slug, b.description,
  b.contact_email::text AS contact_email, b.website_url, b.logo_url, b.status,
  b.analytics_subscribed_at, b.created_at`;

export interface CreateBusinessInput {
  readonly name: string;
  readonly slug: string;
  readonly description: string;
  readonly contactEmail: string | null;
  readonly websiteUrl: string | null;
  readonly logoUrl: string | null;
}

export interface UpdateBusinessInput {
  readonly name?: string;
  readonly description?: string;
  readonly contactEmail?: string | null;
  readonly websiteUrl?: string | null;
  readonly logoUrl?: string | null;
  readonly status?: BusinessStatus;
  readonly analyticsSubscribed?: boolean;
}

@Injectable()
export class BusinessRepository {
  constructor(private readonly database: DatabaseService) {}

  /// What the caller may do for one business, read live rather than from
  /// the token. `status` comes along because a suspended business must stop
  /// answering immediately, not when a token expires.
  async membership(userId: string, businessId: string): Promise<BusinessMembership | null> {
    const result = await this.database.query<{
      business_id: string;
      role: BusinessMemberRole;
      status: BusinessStatus;
      analytics_subscribed_at: Date | null;
    }>(
      `SELECT m.business_id, m.role, b.status, b.analytics_subscribed_at
       FROM business_members m
       JOIN businesses b ON b.id = m.business_id
       WHERE m.user_id = $1 AND m.business_id = $2`,
      [userId, businessId],
    );
    const row = result.rows[0];
    return row
      ? {
          businessId: row.business_id,
          role: row.role,
          status: row.status,
          analyticsSubscribedAt: row.analytics_subscribed_at,
        }
      : null;
  }

  /// Every business the caller belongs to, with its places.
  ///
  /// Suspended ones are included deliberately: the profile has to be able to
  /// say "your dashboard is suspended" rather than silently showing nothing,
  /// which reads to the owner as the app having lost their account.
  async forMember(userId: string): Promise<readonly BusinessSummary[]> {
    const businesses = await this.database.query<BusinessRow & { membership_role: BusinessMemberRole }>(
      `SELECT ${JOINED_BUSINESS_COLUMNS},
              m.role AS membership_role
       FROM business_members m
       JOIN businesses b ON b.id = m.business_id
       WHERE m.user_id = $1
       ORDER BY b.name ASC`,
      [userId],
    );
    if (businesses.rows.length === 0) return [];

    const places = await this.places(businesses.rows.map((row) => row.id));
    return businesses.rows.map((row) => ({
      ...toBusiness(row),
      membershipRole: row.membership_role,
      places: places.get(row.id) ?? [],
    }));
  }

  /// Places for many businesses in one round trip, so `forMember` does not
  /// issue a query per business.
  private async places(businessIds: readonly string[]): Promise<Map<string, BusinessPlace[]>> {
    const result = await this.database.query<{
      business_id: string;
      place_id: string;
      name: string;
      city: string;
      country_code: string;
      category: string;
      is_published: boolean;
      linked_at: Date;
    }>(
      `SELECT bp.business_id, bp.place_id, p.name, p.city, p.country_code,
              p.category, p.is_published, bp.linked_at
       FROM business_places bp
       JOIN map_places p ON p.id = bp.place_id
       WHERE bp.business_id = ANY($1::uuid[])
       ORDER BY p.name ASC`,
      [businessIds],
    );
    const grouped = new Map<string, BusinessPlace[]>();
    for (const row of result.rows) {
      const place: BusinessPlace = {
        placeId: row.place_id,
        name: row.name,
        city: row.city,
        countryCode: row.country_code,
        category: row.category,
        isPublished: row.is_published,
        linkedAt: row.linked_at,
      };
      const existing = grouped.get(row.business_id);
      if (existing) existing.push(place);
      else grouped.set(row.business_id, [place]);
    }
    return grouped;
  }

  /// The place ids a business speaks for — the scope every analytics query
  /// is bounded by (#50).
  async placeIds(businessId: string): Promise<readonly string[]> {
    const result = await this.database.query<{ place_id: string }>(
      'SELECT place_id FROM business_places WHERE business_id = $1',
      [businessId],
    );
    return result.rows.map((row) => row.place_id);
  }

  async findById(businessId: string): Promise<Business | null> {
    const result = await this.database.query<BusinessRow>(
      `SELECT ${BUSINESS_COLUMNS} FROM businesses WHERE id = $1`,
      [businessId],
    );
    return result.rows[0] ? toBusiness(result.rows[0]) : null;
  }

  async list(limit: number, offset: number): Promise<readonly Business[]> {
    const result = await this.database.query<BusinessRow>(
      `SELECT ${BUSINESS_COLUMNS} FROM businesses ORDER BY created_at DESC, id DESC LIMIT $1 OFFSET $2`,
      [limit, offset],
    );
    return result.rows.map(toBusiness);
  }

  async slugExists(slug: string): Promise<boolean> {
    const result = await this.database.query(
      'SELECT 1 FROM businesses WHERE slug = $1',
      [slug],
    );
    return result.rows.length > 0;
  }

  /// Creates the business and its first owner together.
  ///
  /// One transaction because a business with no owner is unreachable: no one
  /// could read its dashboard or appoint anyone who could, and only another
  /// admin write could rescue it. The audit row goes in the same transaction
  /// for the same reason every admin write does.
  async create(
    actorId: string,
    input: CreateBusinessInput,
    ownerUserId: string,
  ): Promise<Business> {
    return this.database.transaction(async (transaction) => {
      const created = await transaction.query<BusinessRow>(
        `INSERT INTO businesses (name, slug, description, contact_email, website_url, logo_url, created_by)
         VALUES ($1, $2, $3, $4, $5, $6, $7)
         RETURNING ${BUSINESS_COLUMNS}`,
        [
          input.name,
          input.slug,
          input.description,
          input.contactEmail,
          input.websiteUrl,
          input.logoUrl,
          actorId,
        ],
      );
      const business = toBusiness(created.rows[0]);

      await transaction.query(
        `INSERT INTO business_members (business_id, user_id, role) VALUES ($1, $2, 'owner')`,
        [business.id, ownerUserId],
      );
      await this.audit(transaction, actorId, 'business.create', business.id, null, {
        ...business,
        ownerUserId,
      });
      return business;
    });
  }

  /// Partial update. Absent fields are left alone rather than nulled, which
  /// is why each one is a separate COALESCE against an explicit sentinel:
  /// `contactEmail: null` means "clear it" and omitting it means "leave it",
  /// and those are different requests.
  async update(
    actorId: string,
    businessId: string,
    input: UpdateBusinessInput,
  ): Promise<Business | null> {
    return this.database.transaction(async (transaction) => {
      const existing = await transaction.query<BusinessRow>(
        `SELECT ${BUSINESS_COLUMNS} FROM businesses WHERE id = $1 FOR UPDATE`,
        [businessId],
      );
      if (existing.rows.length === 0) return null;
      const before = toBusiness(existing.rows[0]);

      const updated = await transaction.query<BusinessRow>(
        `UPDATE businesses SET
           name          = COALESCE($2, name),
           description   = COALESCE($3, description),
           contact_email = CASE WHEN $4::boolean THEN $5::citext ELSE contact_email END,
           website_url   = CASE WHEN $6::boolean THEN $7::text   ELSE website_url   END,
           logo_url      = CASE WHEN $8::boolean THEN $9::text   ELSE logo_url      END,
           status        = COALESCE($10, status),
           -- Absent leaves it alone; true stamps now only if not already
           -- subscribed, so re-granting does not reset the start date a
           -- billing period would be measured from.
           analytics_subscribed_at = CASE
             WHEN $11::boolean IS NULL THEN analytics_subscribed_at
             WHEN $11::boolean THEN COALESCE(analytics_subscribed_at, now())
             ELSE NULL
           END,
           updated_at    = now()
         WHERE id = $1
         RETURNING ${BUSINESS_COLUMNS}`,
        [
          businessId,
          input.name ?? null,
          input.description ?? null,
          input.contactEmail !== undefined,
          input.contactEmail ?? null,
          input.websiteUrl !== undefined,
          input.websiteUrl ?? null,
          input.logoUrl !== undefined,
          input.logoUrl ?? null,
          input.status ?? null,
          input.analyticsSubscribed ?? null,
        ],
      );
      const after = toBusiness(updated.rows[0]);
      await this.audit(transaction, actorId, 'business.update', businessId, before, after);
      return after;
    });
  }

  /// Claims a place for a business.
  ///
  /// Returns 'TAKEN' rather than throwing when another business already owns
  /// it: the UNIQUE constraint on place_id is the real guard, and this turns
  /// its violation into an answer the controller can map to a 409 instead of
  /// a 500. Checking first and inserting after would be a race.
  async linkPlace(
    actorId: string,
    businessId: string,
    placeId: string,
  ): Promise<'LINKED' | 'TAKEN' | 'ALREADY_LINKED'> {
    return this.database.transaction(async (transaction) => {
      const inserted = await transaction.query<{ business_id: string }>(
        `INSERT INTO business_places (business_id, place_id, linked_by)
         VALUES ($1, $2, $3)
         ON CONFLICT (place_id) DO NOTHING
         RETURNING business_id`,
        [businessId, placeId, actorId],
      );
      if (inserted.rows.length > 0) {
        await this.audit(transaction, actorId, 'business.place.link', businessId, null, { placeId });
        return 'LINKED';
      }
      // Nothing inserted: someone owns it. Which someone decides the answer.
      const owner = await transaction.query<{ business_id: string }>(
        'SELECT business_id FROM business_places WHERE place_id = $1',
        [placeId],
      );
      return owner.rows[0]?.business_id === businessId ? 'ALREADY_LINKED' : 'TAKEN';
    });
  }

  async unlinkPlace(actorId: string, businessId: string, placeId: string): Promise<boolean> {
    return this.database.transaction(async (transaction) => {
      const deleted = await transaction.query(
        'DELETE FROM business_places WHERE business_id = $1 AND place_id = $2',
        [businessId, placeId],
      );
      if ((deleted.rowCount ?? 0) === 0) return false;
      await this.audit(transaction, actorId, 'business.place.unlink', businessId, { placeId }, null);
      return true;
    });
  }

  async addMember(
    actorId: string,
    businessId: string,
    userId: string,
    role: BusinessMemberRole,
  ): Promise<void> {
    await this.database.transaction(async (transaction) => {
      await transaction.query(
        `INSERT INTO business_members (business_id, user_id, role)
         VALUES ($1, $2, $3)
         ON CONFLICT (business_id, user_id) DO UPDATE SET role = EXCLUDED.role`,
        [businessId, userId, role],
      );
      await this.audit(transaction, actorId, 'business.member.add', businessId, null, { userId, role });
    });
  }

  /// Removes a member, refusing to remove the last owner.
  ///
  /// A business with no owner cannot appoint one — only an owner may manage
  /// members — so it would be permanently unmanageable by anyone but an
  /// admin. The count and the delete share a transaction, and the SELECT
  /// takes FOR UPDATE, so two concurrent removals cannot each observe two
  /// owners and both proceed.
  async removeMember(
    actorId: string,
    businessId: string,
    userId: string,
  ): Promise<'REMOVED' | 'NOT_A_MEMBER' | 'LAST_OWNER'> {
    return this.database.transaction(async (transaction) => {
      const owners = await transaction.query<{ user_id: string; role: BusinessMemberRole }>(
        `SELECT user_id, role FROM business_members
         WHERE business_id = $1 AND role = 'owner'
         FOR UPDATE`,
        [businessId],
      );
      const target = await transaction.query<{ role: BusinessMemberRole }>(
        'SELECT role FROM business_members WHERE business_id = $1 AND user_id = $2',
        [businessId, userId],
      );
      if (target.rows.length === 0) return 'NOT_A_MEMBER';
      if (target.rows[0].role === 'owner' && owners.rows.length <= 1) return 'LAST_OWNER';

      await transaction.query(
        'DELETE FROM business_members WHERE business_id = $1 AND user_id = $2',
        [businessId, userId],
      );
      await this.audit(transaction, actorId, 'business.member.remove', businessId, { userId }, null);
      return 'REMOVED';
    });
  }

  async members(businessId: string): Promise<readonly {
    userId: string;
    username: string;
    displayName: string;
    role: BusinessMemberRole;
    createdAt: Date;
  }[]> {
    const result = await this.database.query<{
      user_id: string;
      username: string;
      display_name: string;
      role: BusinessMemberRole;
      created_at: Date;
    }>(
      `SELECT m.user_id, p.username, p.display_name, m.role, m.created_at
       FROM business_members m
       JOIN profiles p ON p.id = m.user_id
       WHERE m.business_id = $1
       ORDER BY m.role ASC, p.username ASC`,
      [businessId],
    );
    return result.rows.map((row) => ({
      userId: row.user_id,
      username: row.username,
      displayName: row.display_name,
      role: row.role,
      createdAt: row.created_at,
    }));
  }

  /// Records a privileged write.
  ///
  /// `admin_audit_log` is named for its original users, and most rows here
  /// are still an admin's: creating a business and claiming places for it
  /// are super_admin-only. Member changes are the exception — a business
  /// owner may appoint their own staff — so `actor_id` is not always an
  /// admin. Keeping those rows here anyway is deliberate: the alternative
  /// is no record of who granted someone access to a place's visitor data,
  /// and a slightly wrong table name is much cheaper than that gap. The
  /// action names are namespaced `business.*` so the two are separable.
  private async audit(
    transaction: import('../../../infrastructure/database/database.service.js').DatabaseTransaction,
    actorId: string,
    action: string,
    targetId: string,
    before: unknown,
    after: unknown,
  ): Promise<void> {
    await transaction.query(
      `INSERT INTO admin_audit_log (actor_id, action, target_type, target_id, before_state, after_state)
       VALUES ($1, $2, 'business', $3, $4::jsonb, $5::jsonb)`,
      [
        actorId,
        action,
        targetId,
        before === null ? null : JSON.stringify(before),
        after === null ? null : JSON.stringify(after),
      ],
    );
  }
}
