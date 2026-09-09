import { Injectable, NotFoundException } from '@nestjs/common';
import { ProfilesRepository, type OwnProfileRecord, type PublicProfileRecord, type StreakRecord, type UserXpStatsRecord } from '../infrastructure/profiles.repository.js';
import type { UpdateProfileDto } from '../presentation/profile.dto.js';

@Injectable()
export class ProfilesService {
  constructor(private readonly repository: ProfilesRepository) {}

  async publicProfile(id: string): Promise<PublicProfileRecord> {
    const profile = await this.repository.findPublic(id);
    if (!profile) throw new NotFoundException({ code: 'PROFILE_NOT_FOUND', message: 'Profile not found' });
    return profile;
  }

  async publicProfileByUsername(username: string): Promise<PublicProfileRecord> {
    const profile = await this.repository.findPublicByUsername(username);
    if (!profile) throw new NotFoundException({ code: 'PROFILE_NOT_FOUND', message: 'Profile not found' });
    return profile;
  }

  async ownProfile(id: string): Promise<OwnProfileRecord> {
    const profile = await this.repository.findOwn(id);
    if (!profile) throw new NotFoundException({ code: 'PROFILE_NOT_FOUND', message: 'Profile not found' });
    return profile;
  }

  list(limit: number): Promise<readonly PublicProfileRecord[]> { return this.repository.listByXp(limit); }

  /// Streak for any profile. Public: a streak is visible on profiles the
  /// same way XP and level are, and #46 asks for it on both the viewer's own
  /// home screen and user profiles.
  streak(id: string): Promise<StreakRecord> { return this.repository.streak(id); }

  async xpStats(id: string): Promise<UserXpStatsRecord> {
    const stats = await this.repository.xpStats(id);
    if (!stats) throw new NotFoundException({ code: 'PROFILE_NOT_FOUND', message: 'Profile not found' });
    return stats;
  }

  async update(id: string, input: UpdateProfileDto): Promise<OwnProfileRecord> {
    const profile = await this.repository.update(id, input);
    if (!profile) throw new NotFoundException({ code: 'PROFILE_NOT_FOUND', message: 'Profile not found' });
    return profile;
  }

  setAnalyticsConsent(id: string, consented: boolean): Promise<Date | null> {
    return this.repository.setAnalyticsConsent(id, consented);
  }

  acceptTerms(id: string): Promise<Date> { return this.repository.acceptTerms(id); }

  async accountStatus(id: string): Promise<{ status: string }> {
    const status = await this.repository.accountStatus(id);
    if (!status) throw new NotFoundException({ code: 'ACCOUNT_NOT_FOUND', message: 'Account not found' });
    return { status };
  }
}
