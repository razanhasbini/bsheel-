import type { AuthUser } from '../../../common/auth/auth-user.js';
import { ProfilesService } from '../application/profiles.service.js';
import { AnalyticsConsentDto, UpdateProfileDto } from './profile.dto.js';
declare class ProfileListQuery {
    limit: number;
}
export declare class ProfilesController {
    private readonly service;
    constructor(service: ProfilesService);
    xpStats(user: AuthUser): Promise<import("../infrastructure/profiles.repository.js").UserXpStatsRecord>;
    me(user: AuthUser): Promise<import("../infrastructure/profiles.repository.js").OwnProfileRecord>;
    update(user: AuthUser, body: UpdateProfileDto): Promise<import("../infrastructure/profiles.repository.js").OwnProfileRecord>;
    analyticsConsent(user: AuthUser, body: AnalyticsConsentDto): Promise<{
        analytics_consent_at: Date | null;
    }>;
    acceptTerms(user: AuthUser): Promise<{
        accepted_terms_at: Date;
    }>;
    accountStatus(user: AuthUser): Promise<{
        status: string;
    }>;
    list(query: ProfileListQuery): Promise<readonly import("../infrastructure/profiles.repository.js").PublicProfileRecord[]>;
    get(id: string): Promise<import("../infrastructure/profiles.repository.js").PublicProfileRecord>;
}
export {};
