import { describe, expect, it } from 'vitest';
import { matchesMagic } from '../src/modules/media/application/media.service.js';

describe('matchesMagic', () => {
  it.each([
    ['image/jpeg', Buffer.from([0xff, 0xd8, 0xff, 0xe0])],
    ['image/png', Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])],
    ['image/gif', Buffer.from('GIF89a', 'ascii')],
    ['image/webp', Buffer.from('RIFF0000WEBP', 'ascii')],
    ['video/mp4', Buffer.from([0, 0, 0, 0, 0x66, 0x74, 0x79, 0x70])],
    ['video/webm', Buffer.from([0x1a, 0x45, 0xdf, 0xa3])],
  ])('accepts a valid %s header', (contentType, bytes) => {
    expect(matchesMagic(bytes, contentType)).toBe(true);
  });

  it('rejects a RIFF file that is not WebP', () => {
    expect(matchesMagic(Buffer.from('RIFF0000WAVE', 'ascii'), 'image/webp')).toBe(false);
  });

  it('rejects content whose bytes do not match the declared type', () => {
    expect(matchesMagic(Buffer.from('<html>'), 'image/jpeg')).toBe(false);
  });
});
