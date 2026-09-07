export declare class CreateCollabGroupDto {
    userQuestId: string;
    mode: 'with' | 'versus';
}
export declare class JoinCollabGroupDto {
    code: string;
}
export declare class CollabCodeParam extends JoinCollabGroupDto {
}
export declare class CollabAssignmentParam {
    id: string;
}
export declare class CollabVoteParam {
    groupId: string;
    submissionId: string;
}
