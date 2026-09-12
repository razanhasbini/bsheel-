import { describe, expect, it } from 'vitest';
import { MediaService } from '../src/modules/media/application/media.service.js';

/// The shape gate in front of the signer.
///
/// It is not the authorisation — `authorizeKeys` is — but it is the thing
/// that decides whether a string is even considered an object key, so a
/// mistake here either breaks a whole class of media silently (a poster that
/// never signs, drawn as a placeholder that looks like a bug) or lets a
/// crafted path reach the presigner.
const accepts = (value: string): boolean =>
  // The gate is private because nothing outside the service should consult
  // it; the test reaches it deliberately rather than widening the API.
  (MediaService.prototype as unknown as { extractKey(raw: string): string | null })
    .extractKey.call(null, value) !== null;

const uuid = '3f1c1a52-6d6e-4f0a-9f6e-2b1c9b8a7d61';

describe('media key shape', () => {
  it('accepts the three prefixes that actually store objects', () => {
    expect(accepts(`avatars/${uuid}/a.png`)).toBe(true);
    expect(accepts(`submissions/${uuid}/a.mp4`)).toBe(true);
    // Poster frames cut from video submissions. Added with the map's video
    // tiles; without it every poster silently failed to sign.
    expect(accepts(`posters/${uuid}/a.jpg`)).toBe(true);
  });

  it('refuses anything else, including traversal and other prefixes', () => {
    expect(accepts(`exports/${uuid}/a.jpg`)).toBe(false);
    expect(accepts(`posters/${uuid}/../../etc/passwd`)).toBe(false);
    expect(accepts(`posters/not-a-uuid/a.jpg`)).toBe(false);
    expect(accepts(`/posters/${uuid}/a.jpg`)).toBe(false);
    expect(accepts('')).toBe(false);
  });

  it('accepts the same shapes when they arrive as a URL', () => {
    expect(accepts(`https://cdn.example.com/media/posters/${uuid}/a.jpg`)).toBe(true);
    expect(accepts(`https://cdn.example.com/media/secrets/${uuid}/a.jpg`)).toBe(false);
  });
});
