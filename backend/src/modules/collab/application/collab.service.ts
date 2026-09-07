import { Injectable } from '@nestjs/common';
import { CollabRepository } from '../infrastructure/collab.repository.js';

@Injectable()
export class CollabService {
  constructor(private readonly repository: CollabRepository) {}
  create(userId: string, userQuestId: string, mode: 'with' | 'versus') { return this.repository.create(userId, userQuestId, mode); }
  preview(code: string) { return this.repository.preview(code); }
  join(userId: string, code: string) { return this.repository.join(userId, code); }
  status(userId: string, userQuestId: string) { return this.repository.status(userId, userQuestId); }
  abandon(userId: string, userQuestId: string) { return this.repository.abandon(userId, userQuestId); }
  vote(userId: string, groupId: string, submissionId: string) { return this.repository.vote(userId, groupId, submissionId); }
  unvote(userId: string, groupId: string, submissionId: string) { return this.repository.unvote(userId, groupId, submissionId); }
}
