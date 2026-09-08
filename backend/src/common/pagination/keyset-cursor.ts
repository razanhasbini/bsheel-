import { BadRequestException } from '@nestjs/common';

export interface KeysetCursor {
  context: string;
  at: string;
  id: string;
  score?: number;
  asOf?: string;
}

export function encodeCursor(cursor: KeysetCursor): string {
  return Buffer.from(JSON.stringify(cursor)).toString('base64url');
}

export function decodeCursor(value: string | undefined, context: string): KeysetCursor | undefined {
  if (!value) return undefined;
  try {
    if (value.length > 1024) throw new Error('length');
    const cursor = JSON.parse(Buffer.from(value, 'base64url').toString()) as KeysetCursor;
    if (cursor.context !== context || !validTimestamp(cursor.at)
      || typeof cursor.id !== 'string' || !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(cursor.id)
      || (cursor.score !== undefined && !Number.isFinite(cursor.score))
      || (cursor.asOf !== undefined && !validTimestamp(cursor.asOf))) throw new Error('shape');
    return cursor;
  } catch {
    throw new BadRequestException({ code: 'INVALID_CURSOR', message: 'The pagination cursor is invalid for this list' });
  }
}

function validTimestamp(value: unknown): value is string {
  return typeof value === 'string' && /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?(?:Z|\+00:00)$/.test(value) && Number.isFinite(Date.parse(value));
}
