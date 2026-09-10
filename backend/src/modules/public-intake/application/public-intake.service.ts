import { Injectable } from '@nestjs/common';
import { PublicIntakeRepository } from '../infrastructure/public-intake.repository.js';
import type { SubmitQuestSuggestionDto } from '../presentation/public-intake.dto.js';

@Injectable()
export class PublicIntakeService {
  constructor(private readonly repository: PublicIntakeRepository) {}
  joinWaitlist(email: string, source?: string) { return this.repository.joinWaitlist(email, source); }
  submitSuggestion(input: SubmitQuestSuggestionDto) { return this.repository.submitSuggestion(input); }

  /**
   * Queues a deletion request from the public page.
   *
   * Returns nothing on purpose. The page may only say the request was
   * received, never whether the address has an account.
   */
  requestAccountDeletion(email: string, note?: string) {
    return this.repository.requestAccountDeletion(email, note);
  }
}
