import { PublicIntakeRepository } from '../infrastructure/public-intake.repository.js';
import type { SubmitQuestSuggestionDto } from '../presentation/public-intake.dto.js';
export declare class PublicIntakeService {
    private readonly repository;
    constructor(repository: PublicIntakeRepository);
    joinWaitlist(email: string, source?: string): Promise<import("pg").QueryResultRow>;
    submitSuggestion(input: SubmitQuestSuggestionDto): Promise<import("pg").QueryResultRow>;
}
