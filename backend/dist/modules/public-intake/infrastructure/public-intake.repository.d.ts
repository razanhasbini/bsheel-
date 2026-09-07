import { DatabaseService } from '../../../infrastructure/database/database.service.js';
import type { SubmitQuestSuggestionDto } from '../presentation/public-intake.dto.js';
export declare class PublicIntakeRepository {
    private readonly database;
    constructor(database: DatabaseService);
    joinWaitlist(email: string, source?: string): Promise<import("pg").QueryResultRow>;
    submitSuggestion(input: SubmitQuestSuggestionDto): Promise<import("pg").QueryResultRow>;
}
