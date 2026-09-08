import type { QuestRecord, UserQuestRecord } from '../domain/quest.types.js';
import { QuestsRepository } from '../infrastructure/quests.repository.js';
import type { CreateQuestDto, UpdateQuestDto } from '../presentation/quest.dto.js';
export declare class QuestsService {
    private readonly repository;
    constructor(repository: QuestsRepository);
    getQuest(id: string): Promise<QuestRecord>;
    listAll(): Promise<readonly QuestRecord[]>;
    create(input: CreateQuestDto, actorId: string): Promise<QuestRecord>;
    createBulk(input: readonly CreateQuestDto[], actorId: string): Promise<readonly QuestRecord[]>;
    update(id: string, input: UpdateQuestDto): Promise<QuestRecord>;
    delete(id: string, actorId: string): Promise<void>;
    deleteAll(actorId: string, _confirmation: 'DELETE ALL'): Promise<{
        deleted: number;
    }>;
    active(userId: string): Promise<UserQuestRecord | null>;
    history(userId: string, limit: number, offset: number): Promise<readonly UserQuestRecord[]>;
    assign(userId: string, questId: string): Promise<UserQuestRecord>;
    assignForUser(userId: string, questId: string): Promise<UserQuestRecord>;
    expire(userId: string, userQuestId: string): Promise<void>;
    picker(userId: string, count: number): Promise<readonly QuestRecord[]>;
    qotd(): Promise<Record<string, unknown> | null>;
    followingActive(userId: string, limit: number): Promise<readonly Record<string, unknown>[]>;
    rerollsRemaining(userId: string): Promise<number>;
    reroll(userId: string): Promise<number>;
}
