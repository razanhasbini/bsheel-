import type { AuthUser } from '../../../common/auth/auth-user.js';
import { QuestsService } from '../application/quests.service.js';
import { BulkCreateQuestsDto, CreateQuestDto, DeleteAllQuestsDto, FollowingActiveQueryDto, QuestHistoryQueryDto, QuestIdDto, QuestPickerQueryDto, UpdateQuestDto, UserQuestIdDto } from './quest.dto.js';
declare class AdminAssignQuestDto {
    userId: string;
    questId: string;
}
export declare class QuestsController {
    private readonly service;
    constructor(service: QuestsService);
    active(user: AuthUser): Promise<import("../domain/quest.types.js").UserQuestRecord | null>;
    history(user: AuthUser, query: QuestHistoryQueryDto): Promise<readonly import("../domain/quest.types.js").UserQuestRecord[]>;
    picker(user: AuthUser, query: QuestPickerQueryDto): Promise<readonly import("../domain/quest.types.js").QuestRecord[]>;
    qotd(): Promise<Record<string, unknown> | null>;
    followingActive(user: AuthUser, query: FollowingActiveQueryDto): Promise<readonly Record<string, unknown>[]>;
    rerollsRemaining(user: AuthUser): Promise<{
        remaining: number;
    }>;
    reroll(user: AuthUser): Promise<{
        remaining: number;
    }>;
    assign(user: AuthUser, body: QuestIdDto): Promise<import("../domain/quest.types.js").UserQuestRecord>;
    expire(user: AuthUser, body: UserQuestIdDto): Promise<void>;
    get(id: string): Promise<import("../domain/quest.types.js").QuestRecord>;
    assignForUser(body: AdminAssignQuestDto): Promise<import("../domain/quest.types.js").UserQuestRecord>;
    allAdmin(): Promise<readonly import("../domain/quest.types.js").QuestRecord[]>;
    create(user: AuthUser, body: CreateQuestDto): Promise<import("../domain/quest.types.js").QuestRecord>;
    createBulk(user: AuthUser, body: BulkCreateQuestsDto): Promise<readonly import("../domain/quest.types.js").QuestRecord[]>;
    update(id: string, body: UpdateQuestDto): Promise<import("../domain/quest.types.js").QuestRecord>;
    delete(user: AuthUser, id: string): Promise<void>;
    deleteAll(user: AuthUser, body: DeleteAllQuestsDto): Promise<{
        deleted: number;
    }>;
}
export {};
