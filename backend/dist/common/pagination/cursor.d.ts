export interface ChronologicalCursor {
    readonly createdAt: string;
    readonly id: string;
}
export declare function encodeChronologicalCursor(cursor: ChronologicalCursor): string;
export declare function decodeChronologicalCursor(raw?: string): ChronologicalCursor | undefined;
