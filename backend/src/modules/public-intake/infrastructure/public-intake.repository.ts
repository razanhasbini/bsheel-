import { Injectable } from '@nestjs/common';
import { DatabaseService } from '../../../infrastructure/database/database.service.js';
import type { SubmitQuestSuggestionDto } from '../presentation/public-intake.dto.js';

@Injectable()
export class PublicIntakeRepository {
  constructor(private readonly database: DatabaseService) {}

  async joinWaitlist(email: string, source?: string) {
    return (await this.database.query(
      `INSERT INTO waitlist (email, source) VALUES ($1, $2)
       ON CONFLICT (email) DO UPDATE SET source = COALESCE(waitlist.source, EXCLUDED.source)
       RETURNING id, email::text, source, created_at`, [email, source?.trim() || null],
    )).rows[0];
  }

  async submitSuggestion(input: SubmitQuestSuggestionDto) {
    return (await this.database.query(
      `INSERT INTO quest_suggestions
         (title, description, category, difficulty, suggested_by_name, suggested_by_handle)
       VALUES ($1, $2, $3, $4, $5, $6)
       RETURNING id, status, created_at`,
      [input.title.trim(), input.description.trim(), input.category, input.difficulty,
        input.suggestedByName?.trim() || null, input.suggestedByHandle?.trim() || null],
    )).rows[0];
  }
}
