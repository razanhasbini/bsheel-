export declare class QuestIdDto {
    questId: string;
}
export declare class UserQuestIdDto {
    userQuestId: string;
}
export declare class QuestPickerQueryDto {
    count: number;
}
export declare class FollowingActiveQueryDto {
    limit: number;
}
export declare class QuestHistoryQueryDto {
    limit: number;
    offset: number;
}
export declare class CreateQuestDto {
    title: string;
    description: string;
    category: string;
    difficulty: string;
    xpReward: number;
    durationHours: number;
    isActive: boolean;
}
export declare class UpdateQuestDto {
    title?: string;
    description?: string;
    category?: string;
    difficulty?: string;
    xpReward?: number;
    durationHours?: number;
    isActive?: boolean;
}
export declare class BulkCreateQuestsDto {
    quests: CreateQuestDto[];
}
export declare class DeleteAllQuestsDto {
    confirmation: 'DELETE ALL';
}
