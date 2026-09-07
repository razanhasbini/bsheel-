import { BadRequestException } from '@nestjs/common';
export function encodeChronologicalCursor(cursor) {
    return Buffer.from(JSON.stringify(cursor)).toString('base64url');
}
export function decodeChronologicalCursor(raw) {
    if (!raw)
        return undefined;
    try {
        const value = JSON.parse(Buffer.from(raw, 'base64url').toString('utf8'));
        const createdAt = String(value.createdAt ?? '');
        const id = String(value.id ?? '');
        if (!Number.isFinite(Date.parse(createdAt)) || !/^[0-9a-f-]{36}$/i.test(id))
            throw new Error('invalid');
        return { createdAt, id };
    }
    catch {
        throw new BadRequestException({ code: 'INVALID_CURSOR', message: 'The pagination cursor is invalid' });
    }
}
//# sourceMappingURL=cursor.js.map