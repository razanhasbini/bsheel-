export declare class CursorPaginationDto {
    cursor?: string;
    limit: number;
}
export interface CursorPage<T> {
    readonly items: readonly T[];
    readonly nextCursor: string | null;
    readonly hasMore: boolean;
}
