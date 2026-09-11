import {
  BadRequestException,
  ConflictException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import {
  suggestSlug,
  type Business,
  type BusinessMemberRole,
  type BusinessSummary,
} from '../domain/business.js';
import { BusinessRepository } from '../infrastructure/business.repository.js';
import type { CreateBusinessDto, UpdateBusinessDto } from '../presentation/business.dto.js';

@Injectable()
export class BusinessService {
  constructor(private readonly businesses: BusinessRepository) {}

  /// Every business the signed-in user belongs to. Almost always none or
  /// one; the mobile profile shows the dashboard link when it is non-empty.
  myBusinesses(userId: string): Promise<readonly BusinessSummary[]> {
    return this.businesses.forMember(userId);
  }

  /// The places a business speaks for — the scope for #50's analytics.
  /// Membership is already established by BusinessAccessGuard.
  placeIds(businessId: string): Promise<readonly string[]> {
    return this.businesses.placeIds(businessId);
  }

  async detail(businessId: string): Promise<Business> {
    const business = await this.businesses.findById(businessId);
    if (!business) {
      throw new NotFoundException({ code: 'BUSINESS_NOT_FOUND', message: 'Business not found' });
    }
    return business;
  }

  members(businessId: string) {
    return this.businesses.members(businessId);
  }

  list(limit: number, offset: number): Promise<readonly Business[]> {
    return this.businesses.list(limit, offset);
  }

  /// Creates a business and its first owner.
  ///
  /// The slug is validated rather than auto-resolved on collision: silently
  /// handing back `acme-2` when the admin asked for `acme` makes the URL
  /// they are about to send someone quietly wrong.
  async create(actorId: string, input: CreateBusinessDto): Promise<Business> {
    const slug = (input.slug ?? suggestSlug(input.name)).trim();
    if (!slug) {
      throw new BadRequestException({
        code: 'BUSINESS_SLUG_REQUIRED',
        message: 'A URL handle could not be derived from this name; supply one explicitly',
      });
    }
    if (await this.businesses.slugExists(slug)) {
      throw new ConflictException({
        code: 'BUSINESS_SLUG_TAKEN',
        message: 'That URL handle is already in use',
      });
    }
    try {
      return await this.businesses.create(
        actorId,
        {
          name: input.name.trim(),
          slug,
          description: input.description ?? '',
          contactEmail: input.contactEmail ?? null,
          websiteUrl: input.websiteUrl ?? null,
          logoUrl: input.logoUrl ?? null,
        },
        input.ownerUserId,
      );
    } catch (error) {
      // The check above narrows the window; the UNIQUE constraint closes it.
      // Two admins creating the same handle at once both pass the check and
      // one loses here, which is a conflict rather than a server fault.
      if (isUniqueViolation(error)) {
        throw new ConflictException({
          code: 'BUSINESS_SLUG_TAKEN',
          message: 'That URL handle is already in use',
        });
      }
      if (isForeignKeyViolation(error)) {
        throw new BadRequestException({
          code: 'BUSINESS_OWNER_NOT_FOUND',
          message: 'The nominated owner is not an existing user',
        });
      }
      throw error;
    }
  }

  async update(actorId: string, businessId: string, input: UpdateBusinessDto): Promise<Business> {
    const updated = await this.businesses.update(actorId, businessId, input);
    if (!updated) {
      throw new NotFoundException({ code: 'BUSINESS_NOT_FOUND', message: 'Business not found' });
    }
    return updated;
  }

  async linkPlace(actorId: string, businessId: string, placeId: string): Promise<void> {
    await this.detail(businessId);
    let outcome: 'LINKED' | 'TAKEN' | 'ALREADY_LINKED';
    try {
      outcome = await this.businesses.linkPlace(actorId, businessId, placeId);
    } catch (error) {
      if (isForeignKeyViolation(error)) {
        throw new NotFoundException({ code: 'PLACE_NOT_FOUND', message: 'Place not found' });
      }
      throw error;
    }
    if (outcome === 'TAKEN') {
      throw new ConflictException({
        code: 'PLACE_ALREADY_CLAIMED',
        message: 'Another business already owns this place',
      });
    }
  }

  async unlinkPlace(actorId: string, businessId: string, placeId: string): Promise<void> {
    const removed = await this.businesses.unlinkPlace(actorId, businessId, placeId);
    if (!removed) {
      throw new NotFoundException({
        code: 'PLACE_NOT_LINKED',
        message: 'This place is not linked to this business',
      });
    }
  }

  async addMember(
    actorId: string,
    businessId: string,
    userId: string,
    role: BusinessMemberRole,
  ): Promise<void> {
    await this.detail(businessId);
    try {
      await this.businesses.addMember(actorId, businessId, userId, role);
    } catch (error) {
      if (isForeignKeyViolation(error)) {
        throw new NotFoundException({ code: 'USER_NOT_FOUND', message: 'User not found' });
      }
      throw error;
    }
  }

  async removeMember(actorId: string, businessId: string, userId: string): Promise<void> {
    const outcome = await this.businesses.removeMember(actorId, businessId, userId);
    if (outcome === 'NOT_A_MEMBER') {
      throw new NotFoundException({
        code: 'NOT_A_BUSINESS_MEMBER',
        message: 'That user is not a member of this business',
      });
    }
    if (outcome === 'LAST_OWNER') {
      // Allowing this would leave a business only an admin could ever
      // manage again, since appointing members is owner-only.
      throw new ConflictException({
        code: 'LAST_BUSINESS_OWNER',
        message: 'A business must keep at least one owner; appoint another before removing this one',
      });
    }
  }
}

const errorCode = (error: unknown): string | undefined =>
  typeof error === 'object' && error !== null && 'code' in error
    ? String((error as { code: unknown }).code)
    : undefined;

const isUniqueViolation = (error: unknown): boolean => errorCode(error) === '23505';
const isForeignKeyViolation = (error: unknown): boolean => errorCode(error) === '23503';
