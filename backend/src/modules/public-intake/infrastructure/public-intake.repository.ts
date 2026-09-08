import { Injectable } from '@nestjs/common';
import { DatabaseService } from '../../../infrastructure/database/database.service.js';
import type { SubmitQuestSuggestionDto } from '../presentation/public-intake.dto.js';

@Injectable()
export class PublicIntakeRepository {
  constructor(private readonly database: DatabaseService) {}

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
