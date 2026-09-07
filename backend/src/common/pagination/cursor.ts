import { BadRequestException } from '@nestjs/common';

export interface ChronologicalCursor {
  readonly createdAt: string;
  readonly id: string;
}

export function encodeChronologicalCursor(cursor: ChronologicalCursor): string {
  return Buffer.from(JSON.stringify(cursor)).toString('base64url');
}

export function decodeChronologicalCursor(raw?: string): ChronologicalCursor | undefined {
  if (!raw) return undefined;
  try {
    const value = JSON.parse(Buffer.from(raw, 'base64url').toString('utf8')) as Record<string, unknown>;
    const createdAt = String(value.createdAt ?? '');
    const id = String(value.id ?? '');
    if (!Number.isFinite(Date.parse(createdAt)) || !/^[0-9a-f-]{36}$/i.test(id)) throw new Error('invalid');
    return { createdAt, id };
  } catch {
    throw new BadRequestException({ code: 'INVALID_CURSOR', message: 'The pagination cursor is invalid' });
  }
}
