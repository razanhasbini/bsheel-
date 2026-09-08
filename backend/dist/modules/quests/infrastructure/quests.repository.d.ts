import { DatabaseService } from '../../../infrastructure/database/database.service.js';
import type { QuestRecord, UserQuestRecord } from '../domain/quest.types.js';
import type { CreateQuestDto, UpdateQuestDto } from '../presentation/quest.dto.js';
export declare class QuestsRepository {
    private readonly database;
    constructor(database: DatabaseService);
    findQuest(id: string): Promise<QuestRecord | null>;
    listAll(): Promise<readonly QuestRecord[]>;
    create(input: CreateQuestDto, actorId: string): Promise<QuestRecord>;
    createBulk(input: readonly CreateQuestDto[], actorId: string): Promise<readonly QuestRecord[]>;
    update(id: string, input: UpdateQuestDto): Promise<QuestRecord | null>;
    delete(id: string, actorId: string): Promise<void>;
    deleteAll(actorId: string): Promise<{
        deleted: number;
    }>;
    findActiveForUser(userId: string): Promise<UserQuestRecord | null>;
    history(userId: string, limit: number, offset: number): Promise<readonly UserQuestRecord[]>;
    assignSpecific(userId: string, questId: string, displaceActive?: boolean): Promise<UserQuestRecord>;
    expire(userId: string, userQuestId: string): Promise<void>;
    pickerOptions(userId: string, requestedCount: number): Promise<readonly QuestRecord[]>;
    questOfTheDay(): Promise<Record<string, unknown> | null>;
    followingActive(userId: string, limit: number): Promise<readonly Record<string, unknown>[]>;
    rerollsRemaining(userId: string): Promise<number>;
    recordReroll(userId: string): Promise<number>;
    private lockUser;
    private expireOverdueForUser;
    private insertAssignmentNotification;
    private emitQuest;
    private isForeignKeyViolation;
}
