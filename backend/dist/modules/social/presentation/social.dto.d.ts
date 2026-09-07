export declare class VoteDto {
    type: 'upvote' | 'downvote';
}
export declare class AddCommentDto {
    body: string;
    parentId?: string;
}
export declare class BlockUserDto {
    reason: string;
}
export declare class ReportContentDto {
    reportedType: 'submission' | 'comment' | 'user';
    reportedId: string;
    reason: string;
}
