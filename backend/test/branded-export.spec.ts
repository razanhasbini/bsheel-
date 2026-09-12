import { describe, expect, it } from 'vitest';
import {
  BAND,
  bandText,
  firstMediaKey,
  wrapWords,
} from '../src/modules/media/infrastructure/branded-export.processor.js';
import type { BrandedExportSource } from '../src/modules/media/infrastructure/branded-export.repository.js';

const source: BrandedExportSource = {
  submissionId: '00000000-0000-4000-8000-000000000001',
  mediaKey: 'submissions/00000000-0000-4000-8000-000000000002/clip.mp4',
  mediaType: 'video/mp4',
  questTitle: 'Show how big Raouché Pigeon Rocks really is',
  username: 'tayseer',
  submittedAt: new Date('2026-09-12T15:14:00Z'),
  placeName: 'Raouché Pigeon Rocks',
  countryName: 'Lebanon',
};

describe('branded export band text', () => {
  it('carries the wordmark, the whole quest title and who/when/where on a phone-shaped clip', () => {
    const band = Math.round(1920 * BAND.heightFraction);
    const text = bandText(source, 1080, band);
    expect(text.wordmark).toBe('BSHEEL');
    expect(text.titleLines.join(' ')).toBe(source.questTitle);
    expect(text.titleLines.length).toBeLessThanOrEqual(2);
    expect(text.meta).toBe('@tayseer  ·  2026-09-12  ·  Raouché Pigeon Rocks');
    // Bounded by the width, not only the band: a tall clip must not get a
    // title wider than the frame.
    expect(text.sizes.title).toBeLessThanOrEqual(1080 * 0.05);
  });

  it('wraps to two lines and clips with an ellipsis past that, because drawtext does not wrap', () => {
    const band = Math.round(640 * BAND.heightFraction);
    const text = bandText({ ...source, questTitle: 'word '.repeat(80).trim() }, 360, band);
    expect(text.titleLines).toHaveLength(2);
    expect(text.titleLines[1].endsWith('…')).toBe(true);
    for (const line of text.titleLines) expect(line.length).toBeLessThanOrEqual(40);
  });

  it('falls back to the country when the post has no place, and omits both when neither', () => {
    expect(bandText({ ...source, placeName: null }, 1080, 200).meta).toContain('Lebanon');
    expect(bandText({ ...source, placeName: null, countryName: null }, 1080, 200).meta)
      .toBe('@tayseer  ·  2026-09-12');
  });
});

describe('wrapWords', () => {
  it('keeps short text on one line and never splits a word', () => {
    expect(wrapWords('Learn a simple song', 40, 2)).toEqual(['Learn a simple song']);
    expect(wrapWords('Learn a simple song', 8, 2)).toEqual(['Learn a', 'simple…']);
  });
});

describe('firstMediaKey', () => {
  it('returns a plain key as is and the first of a JSON array', () => {
    expect(firstMediaKey('submissions/x/a.mp4')).toBe('submissions/x/a.mp4');
    expect(firstMediaKey('["submissions/x/a.mp4","submissions/x/b.jpg"]')).toBe('submissions/x/a.mp4');
    expect(firstMediaKey('[not json')).toBe('[not json');
  });
});
