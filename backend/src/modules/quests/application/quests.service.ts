import { Injectable, NotFoundException } from '@nestjs/common';
import type { QuestRecord, UserQuestRecord } from '../domain/quest.types.js';
import { QuestsRepository } from '../infrastructure/quests.repository.js';
import type { CreateQuestDto, UpdateQuestDto } from '../presentation/quest.dto.js';

@Injectable()
export class QuestsService {
  constructor(private readonly repository: QuestsRepository) {}

  async getQuest(id: string): Promise<QuestRecord> {
    const quest = await this.repository.findQuest(id);
    if (!quest) throw new NotFoundException({ code: 'QUEST_NOT_FOUND', message: 'Quest not found' });
    return quest;
  }

  listAll(): Promise<readonly QuestRecord[]> { return this.repository.listAll(); }
  create(input: CreateQuestDto, actorId: string): Promise<QuestRecord> { return this.repository.create(input, actorId); }
  createBulk(input: readonly CreateQuestDto[], actorId: string): Promise<readonly QuestRecord[]> {
    return this.repository.createBulk(input, actorId);
  }
  async update(id: string, input: UpdateQuestDto): Promise<QuestRecord> {
    const quest = await this.repository.update(id, input);
    if (!quest) throw new NotFoundException({ code: 'QUEST_NOT_FOUND', message: 'Quest not found' });
    return quest;
  }
  delete(id: string, actorId: string): Promise<void> { return this.repository.delete(id, actorId); }
  deleteAll(actorId: string, _confirmation: 'DELETE ALL') { return this.repository.deleteAll(actorId); }
  active(userId: string): Promise<UserQuestRecord | null> { return this.repository.findActiveForUser(userId); }
  history(userId: string, limit: number, offset: number): Promise<readonly UserQuestRecord[]> {
    return this.repository.history(userId, limit, offset);
  }
  assign(userId: string, questId: string): Promise<UserQuestRecord> { return this.repository.assignSpecific(userId, questId); }
  expire(userId: string, userQuestId: string): Promise<void> { return this.repository.expire(userId, userQuestId); }
  picker(userId: string, count: number): Promise<readonly QuestRecord[]> { return this.repository.pickerOptions(userId, count); }
  qotd(): Promise<Record<string, unknown> | null> { return this.repository.questOfTheDay(); }
  followingActive(userId: string, limit: number): Promise<readonly Record<string, unknown>[]> { return this.repository.followingActive(userId, limit); }
  rerollsRemaining(userId: string): Promise<number> { return this.repository.rerollsRemaining(userId); }
  reroll(userId: string): Promise<number> { return this.repository.recordReroll(userId); }
}
