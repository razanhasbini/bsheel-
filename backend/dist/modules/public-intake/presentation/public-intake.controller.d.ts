import { PublicIntakeService } from '../application/public-intake.service.js';
import { JoinWaitlistDto, SubmitQuestSuggestionDto } from './public-intake.dto.js';
export declare class PublicIntakeController {
    private readonly service;
    constructor(service: PublicIntakeService);
    joinWaitlist(body: JoinWaitlistDto): Promise<import("pg").QueryResultRow>;
    suggest(body: SubmitQuestSuggestionDto): Promise<import("pg").QueryResultRow>;
}
