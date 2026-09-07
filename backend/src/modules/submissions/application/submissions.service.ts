import { Injectable, NotFoundException } from '@nestjs/common';
import { SubmissionsRepository, type SubmissionRecord } from '../infrastructure/submissions.repository.js';
import type { CreateSubmissionDto } from '../presentation/submission.dto.js';

@Injectable()
export class SubmissionsService {
  constructor(private readonly repository: SubmissionsRepository) {}

  create(userId: string, input: CreateSubmissionDto): Promise<SubmissionRecord> { return this.repository.create(userId, input); }
  async detail(id: string, viewerId: string): Promise<Record<string, unknown>> {
    const row = await this.repository.findVisibleToUser(id, viewerId);
    if (!row) throw new NotFoundException({ code: 'SUBMISSION_NOT_FOUND', message: 'Submission not found' });
    return row;
  }
  listUser(userId: string, viewerId: string, limit: number, offset: number) { return this.repository.listUser(userId, viewerId, limit, offset); }
  listPending(limit: number, offset: number) { return this.repository.listPending(limit, offset); }
  appeal(userId: string, id: string, note: string) { return this.repository.appeal(userId, id, note); }
  approve(actorId: string | null, id: string, note?: string, source?: Record<string, unknown>) {
    return this.repository.approve(actorId, id, note, source);
  }
  reject(actorId: string | null, id: string, note: string, source?: Record<string, unknown>) {
    return this.repository.reject(actorId, id, note, source);
  }
  visibility(userId: string, id: string, visibility: 'visible' | 'hidden_from_feed' | 'deleted') {
    return this.repository.setVisibility(userId, id, visibility);
  }
  removeByAdmin(actorId: string, id: string, reason: string) {
    return this.repository.removeByAdmin(actorId, id, reason);
  }
}
