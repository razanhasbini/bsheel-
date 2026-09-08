import { ProfilesRepository, type OwnProfileRecord, type PublicProfileRecord, type UserXpStatsRecord } from '../infrastructure/profiles.repository.js';
import type { UpdateProfileDto } from '../presentation/profile.dto.js';
export declare class ProfilesService {
    private readonly repository;
    constructor(repository: ProfilesRepository);
    publicProfile(id: string): Promise<PublicProfileRecord>;
    publicProfileByUsername(username: string): Promise<PublicProfileRecord>;
    ownProfile(id: string): Promise<OwnProfileRecord>;
    list(limit: number): Promise<readonly PublicProfileRecord[]>;
    xpStats(id: string): Promise<UserXpStatsRecord>;
    update(id: string, input: UpdateProfileDto): Promise<OwnProfileRecord>;
    setAnalyticsConsent(id: string, consented: boolean): Promise<Date | null>;
    acceptTerms(id: string): Promise<Date>;
    accountStatus(id: string): Promise<{
        status: string;
    }>;
}
