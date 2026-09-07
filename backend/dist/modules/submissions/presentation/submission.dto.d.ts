export declare class CreateSubmissionDto {
    userQuestId: string;
    mediaUrl: string;
    mediaType: 'image' | 'video' | 'mixed';
    caption?: string;
    showInFeed: boolean;
}
export declare class AppealSubmissionDto {
    appealNote: string;
}
export declare class ReviewSubmissionDto {
    reviewNote?: string;
}
export declare class RejectSubmissionDto {
    reviewNote: string;
}
export declare class SetVisibilityDto {
    visibility: 'visible' | 'hidden_from_feed' | 'deleted';
}
