import { Injectable } from '@nestjs/common';
import { DatabaseService } from '../../../infrastructure/database/database.service.js';
import type { SubmitQuestSuggestionDto } from '../presentation/public-intake.dto.js';

@Injectable()
export class PublicIntakeRepository {
  constructor(private readonly database: DatabaseService) {}

  /**
   * Records a deletion request from the public page.
   *
   * Does NOT delete anything, and cannot: the caller is unauthenticated, so
   * acting on an email address alone would let anyone erase anyone's account.
   * The row is a queue entry for an operator who verifies identity and then
   * runs the authenticated flow.
   *
   * `matched_user_id` is resolved here so the operator can see whether there
   * is anything to erase, but the return value says nothing about it — the
   * endpoint is public, and a response that differed for a known address
   * would be an account-enumeration oracle.
   */
  async requestAccountDeletion(email: string, note?: string): Promise<void> {
    await this.database.query(
      `INSERT INTO public_deletion_requests (email, note, matched_user_id)
       VALUES ($1::citext, $2, (SELECT id FROM users WHERE email = $1::citext AND deleted_at IS NULL))
       ON CONFLICT (email) WHERE handled_at IS NULL
       DO UPDATE SET note = COALESCE(EXCLUDED.note, public_deletion_requests.note)`,
      [email, note?.trim() || null],
    );
  }

  async joinWaitlist(email: string, source?: string) {
    return this.database.typed.insertInto('waitlist')
      .values({ email, source: source?.trim() || null })
      .onConflict((conflict) => conflict.column('email').doUpdateSet((eb) => ({
        source: eb.fn.coalesce('waitlist.source', eb.ref('excluded.source')),
      })))
      .returning(['id', 'email', 'source', 'created_at'])
      .executeTakeFirstOrThrow();
  }

  async submitSuggestion(input: SubmitQuestSuggestionDto) {
    return this.database.typed.insertInto('quest_suggestions').values({
      title: input.title.trim(), description: input.description.trim(),
      category: input.category, difficulty: input.difficulty,
      suggested_by_name: input.suggestedByName?.trim() || null,
      suggested_by_handle: input.suggestedByHandle?.trim() || null,
    }).returning(['id', 'status', 'created_at']).executeTakeFirstOrThrow();
  }
}
