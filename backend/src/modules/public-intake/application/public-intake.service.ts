import { Injectable } from '@nestjs/common';
import { PublicIntakeRepository } from '../infrastructure/public-intake.repository.js';
import type { SubmitQuestSuggestionDto } from '../presentation/public-intake.dto.js';

@Injectable()
export class PublicIntakeService {
  constructor(private readonly repository: PublicIntakeRepository) {}
  joinWaitlist(email: string, source?: string) { return this.repository.joinWaitlist(email, source); }
  submitSuggestion(input: SubmitQuestSuggestionDto) { return this.repository.submitSuggestion(input); }
}
