import { DatabaseService } from '../../../infrastructure/database/database.service.js';
import type { UpdateProfileDto } from '../presentation/profile.dto.js';
export interface PublicProfileRecord {
    readonly id: string;
    readonly username: string;
    readonly display_name: string;
    readonly avatar_url: string | null;
    readonly bio: string | null;
    readonly xp: number;
    readonly level: number;
    readonly quests_completed: number;
    readonly profile_completed: boolean;
    readonly created_at: Date;
    readonly updated_at: Date;
}
export interface OwnProfileRecord extends PublicProfileRecord {
    readonly age_verified: boolean;
    readonly analytics_consent_at: Date | null;
}
export interface UserXpStatsRecord {
    readonly total_xp: number;
    readonly current_level: number;
    readonly xp_to_next_level: number;
    readonly total_quests: number;
    readonly rank: number;
}
export declare class ProfilesRepository {
    private readonly database;
    constructor(database: DatabaseService);
    findPublic(id: string): Promise<PublicProfileRecord | null>;
    findPublicByUsername(username: string): Promise<PublicProfileRecord | null>;
    findOwn(id: string): Promise<OwnProfileRecord | null>;
    xpStats(id: string): Promise<UserXpStatsRecord | null>;
    listByXp(limit: number): Promise<readonly PublicProfileRecord[]>;
    update(id: string, input: UpdateProfileDto): Promise<OwnProfileRecord | null>;
    setAnalyticsConsent(id: string, consented: boolean): Promise<Date | null>;
    acceptTerms(id: string): Promise<Date>;
    accountStatus(id: string): Promise<string | null>;
    private emitUpdated;
}
