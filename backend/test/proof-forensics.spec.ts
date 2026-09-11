import exifr from 'exifr';
import sharp from 'sharp';
import { beforeAll, describe, expect, it } from 'vitest';
import {
  buildForensicsReport,
  classifyCaptureWindow,
  declaresGeneratedContent,
  differenceHash,
  hammingDistance,
  isNearDuplicate,
  matchesScreenResolution,
  nearDuplicateThreshold,
  type ExifFacts,
  type ForensicCode,
} from '../src/modules/submissions/domain/proof-forensics.js';
import {
  cameraPhoto,
  grayscale9x8,
  reEncodedCopy,
  screenshot,
  unrelatedPhoto,
} from './support/proof-fixtures.js';

const noExif: ExifFacts = { capturedAtHasOffset: false, hasGps: false };
const assignedAt = new Date('2026-09-09T08:00:00Z');
const submittedAt = new Date('2026-09-09T10:00:00Z');

const codes = (input: Parameters<typeof buildForensicsReport>[0]): ForensicCode[] =>
  buildForensicsReport(input).findings.map((finding) => finding.code);

describe('differenceHash, against real encoded images', () => {
  let original: string;
  let reEncoded: string;
  let unrelated: string;

  /// The fixtures are textured on purpose, so each of these is a real hash
  /// rather than the null a featureless frame now produces. Asserted here so
  /// a fixture that lost its structure fails loudly instead of turning every
  /// assertion below into a comparison against null.
  const hashOf = async (image: Buffer): Promise<string> => {
    const hash = differenceHash(await grayscale9x8(image));
    expect(hash).not.toBeNull();
    return hash!;
  };

  beforeAll(async () => {
    original = await hashOf(await cameraPhoto());
    reEncoded = await hashOf(await reEncodedCopy());
    unrelated = await hashOf(await unrelatedPhoto());
  });

  it('produces 64 bits', () => {
    expect(original).toHaveLength(64);
    expect(original).toMatch(/^[01]{64}$/);
  });

  // A flat image hashes to all zeroes and every comparison is vacuously
  // equal, so the fixture has to carry real gradient structure for any of
  // these assertions to mean anything.
  it('produces a non-degenerate hash for a textured image', () => {
    expect(original).not.toBe('0'.repeat(64));
    expect(original).not.toBe('1'.repeat(64));
  });

  // The case that matters: the common recycling move is re-saving or
  // re-sharing, which resizes and recompresses. If the hash did not survive
  // that, near-duplicate detection would be worthless.
  it('survives resize and heavy recompression of the same picture', () => {
    const distance = hammingDistance(original, reEncoded);
    expect(distance).toBeLessThanOrEqual(nearDuplicateThreshold);
    expect(isNearDuplicate(original, reEncoded)).toBe(true);
  });

  // The other half of the threshold's job. Without this, a threshold that
  // passes the test above could simply be matching everything.
  it('separates a genuinely different picture by a wide margin', () => {
    const distance = hammingDistance(original, unrelated);
    expect(distance).toBeGreaterThan(nearDuplicateThreshold);
    expect(isNearDuplicate(original, unrelated)).toBe(false);
  });

  /// The dangerous degeneracy, and the reason a hash can now be absent.
  ///
  /// A hash of 64 identical bits is shared by every frame with the same
  /// property, so two such frames sit at Hamming distance 0 — well inside
  /// the near-duplicate threshold — on the strength of a fingerprint that
  /// describes neither. A near duplicate not owned by this user is weighted
  /// `decisive`, so the outcome is a measurement accusing an honest player
  /// of submitting stolen proof.
  ///
  /// It surfaced as an intermittent e2e failure, because it needed two such
  /// images to exist in the same database at the same time.
  describe('a frame whose hash would distinguish nothing', () => {
    const flat = (level: number) => new Uint8Array(72).fill(level);

    /// A monotonic left-to-right ramp, repeated on every row.
    const ramp = (from: number, step: number) => {
      const bitmap = new Uint8Array(72);
      for (let row = 0; row < 8; row += 1) {
        for (let column = 0; column < 9; column += 1) {
          bitmap[row * 9 + column] = from + column * step;
        }
      }
      return bitmap;
    };

    it('gets no hash at all, rather than one that matches everything', () => {
      expect(differenceHash(flat(0))).toBeNull();
      expect(differenceHash(flat(22))).toBeNull();
      expect(differenceHash(flat(245))).toBeNull();
    });

    // The collision that broke the build. Before the guard a dark
    // screenshot, a white wall and a night sky were three different pictures
    // at distance 0 from one another.
    it('does not let a dark screen, a white wall and a night sky collide', () => {
      for (const level of [4, 22, 245]) {
        expect(differenceHash(flat(level)), `level ${level}`).toBeNull();
      }
    });

    // The half a range check would have missed. A sky at dawn has plenty of
    // dynamic range and still brightens in one direction everywhere, so
    // every comparison reads the same and the hash is just as degenerate —
    // for a real reason rather than for want of information.
    it('refuses a smooth one-directional gradient, however wide its range', () => {
      expect(differenceHash(ramp(0, 30))).toBeNull();
      expect(differenceHash(ramp(10, 3))).toBeNull();
    });

    // And the guard must not swallow a real picture. Structure in more than
    // one direction produces both bit values, which is all it takes.
    it('still hashes a frame with structure in it', () => {
      const textured = new Uint8Array(72);
      for (let index = 0; index < 72; index += 1) {
        textured[index] = index % 2 === 0 ? 40 : 90;
      }
      const hash = differenceHash(textured);
      expect(hash).not.toBeNull();
      expect(hash).toContain('0');
      expect(hash).toContain('1');
    });
  });

  it('rejects a bitmap that is not 9x8', () => {
    expect(() => differenceHash(new Uint8Array(64))).toThrow(/9x8/);
  });

  it('refuses to compare hashes of different lengths', () => {
    expect(() => hammingDistance('01', '0101')).toThrow(/length mismatch/);
  });
});

describe('EXIF extraction from real files', () => {
  it('reads camera tags and an offset-qualified capture time', async () => {
    const captured = new Date('2026-09-09T09:15:00Z');
    const image = await cameraPhoto({ capturedAt: captured, offsetTimeOriginal: '+03:00' });
    const parsed = await exifr.parse(image, {
      pick: ['Make', 'Model', 'DateTimeOriginal', 'OffsetTimeOriginal'],
    });
    expect(parsed.Make).toBe('Apple');
    expect(parsed.Model).toBe('iPhone 17 Pro');
    expect(parsed.OffsetTimeOriginal).toBe('+03:00');
    expect(parsed.DateTimeOriginal).toBeInstanceOf(Date);
  });

  // The screenshot signal is an absence, so it has to be an absence in a real
  // file rather than an object we chose not to populate.
  it('finds no EXIF at all in a screenshot-shaped PNG', async () => {
    const parsed = await exifr.parse(await screenshot()).catch(() => undefined);
    expect(parsed?.Make).toBeUndefined();
    expect(parsed?.DateTimeOriginal).toBeUndefined();
    const meta = await sharp(await screenshot()).metadata();
    expect(matchesScreenResolution(meta.width!, meta.height!)).toBe(true);
  });
});

describe('classifyCaptureWindow', () => {
  it('accepts a capture between assignment and submission', () => {
    const exif: ExifFacts = {
      capturedAt: new Date('2026-09-09T09:00:00Z'),
      capturedAtHasOffset: true,
      hasGps: false,
    };
    expect(classifyCaptureWindow(exif, assignedAt, submittedAt)).toBe('within_window');
  });

  it('flags a capture before the quest existed when the offset is known', () => {
    const exif: ExifFacts = {
      capturedAt: new Date('2026-09-08T09:00:00Z'),
      capturedAtHasOffset: true,
      hasGps: false,
    };
    expect(classifyCaptureWindow(exif, assignedAt, submittedAt)).toBe('predates_assignment');
  });

  // THE false-positive guard. EXIF DateTimeOriginal is local wall-clock with
  // no zone: a truthful player in Apia (UTC+13) photographing their quest
  // minutes after assignment writes a wall-clock time that reads as hours
  // *before* the UTC assignment. Without the tolerance this system would
  // tell honest players in half the world that they faked their proof.
  it('does NOT flag a zoneless capture that only a timezone can explain', () => {
    const exif: ExifFacts = {
      // Ten hours "before" assignment — impossible as an instant, ordinary as
      // a wall-clock reading from a positive UTC offset.
      capturedAt: new Date('2026-09-08T22:00:00Z'),
      capturedAtHasOffset: false,
      hasGps: false,
    };
    expect(classifyCaptureWindow(exif, assignedAt, submittedAt)).toBe('within_window');
  });

  // The tolerance is wide, not infinite: real recycling from days earlier
  // still has to be caught, or the guard above would defeat the check.
  it('still flags a zoneless capture from well outside any timezone', () => {
    const exif: ExifFacts = {
      capturedAt: new Date('2026-09-01T09:00:00Z'),
      capturedAtHasOffset: false,
      hasGps: false,
    };
    expect(classifyCaptureWindow(exif, assignedAt, submittedAt)).toBe('predates_assignment');
  });

  it('treats a capture after submission as clock skew, not fraud', () => {
    const exif: ExifFacts = {
      capturedAt: new Date('2026-09-11T09:00:00Z'),
      capturedAtHasOffset: true,
      hasGps: false,
    };
    expect(classifyCaptureWindow(exif, assignedAt, submittedAt)).toBe('after_submission');
  });

  it('tolerates submitting immediately after shooting', () => {
    const exif: ExifFacts = {
      capturedAt: new Date('2026-09-09T10:03:00Z'),
      capturedAtHasOffset: true,
      hasGps: false,
    };
    expect(classifyCaptureWindow(exif, assignedAt, submittedAt)).toBe('within_window');
  });

  it('reports unknown when there is no capture time', () => {
    expect(classifyCaptureWindow(noExif, assignedAt, submittedAt)).toBe('unknown');
  });
});

describe('matchesScreenResolution', () => {
  it('matches a device screen in either orientation', () => {
    expect(matchesScreenResolution(1179, 2556)).toBe(true);
    expect(matchesScreenResolution(2556, 1179)).toBe(true);
    expect(matchesScreenResolution(1920, 1080)).toBe(true);
  });

  it('does not match ordinary camera dimensions', () => {
    expect(matchesScreenResolution(4032, 3024)).toBe(false);
    expect(matchesScreenResolution(640, 480)).toBe(false);
  });
});

describe('declaresGeneratedContent', () => {
  it('recognises generator software tags', () => {
    for (const tag of ['Midjourney v7', 'DALL-E 3', 'Stable Diffusion XL', 'Adobe Firefly']) {
      expect(declaresGeneratedContent(tag)).toBe(true);
    }
  });

  // Ordinary editing must not be treated as fabrication: cropping and
  // filtering are what normal users do to normal photographs.
  it('does not treat ordinary editing as generated', () => {
    for (const tag of ['Adobe Photoshop 26.0', 'GIMP 3.0', 'iOS 26.1', undefined]) {
      expect(declaresGeneratedContent(tag)).toBe(false);
    }
  });
});

describe('buildForensicsReport', () => {
  const base = {
    exif: { capturedAt: new Date('2026-09-09T09:00:00Z'), capturedAtHasOffset: true, hasGps: false, cameraMake: 'Apple' },
    image: { width: 4032, height: 3024, format: 'jpeg' },
    assignedAt,
    submittedAt,
  };

  it('clears a clean camera photograph for automated approval', () => {
    const report = buildForensicsReport(base);
    expect(report.captureWindow).toBe('within_window');
    expect(report.blocksAutomatedApproval).toBe(false);
    expect(report.findings.map((f) => f.code)).toContain('capture_within_window');
  });

  it('blocks approval when the capture predates assignment', () => {
    const report = buildForensicsReport({
      ...base,
      exif: { ...base.exif, capturedAt: new Date('2026-09-01T09:00:00Z') },
    });
    expect(report.blocksAutomatedApproval).toBe(true);
    expect(report.findings.find((f) => f.code === 'capture_predates_assignment')?.weight).toBe('decisive');
  });

  it('blocks approval on byte-identical proof, and says whose it was', () => {
    const own = buildForensicsReport({
      ...base,
      exactDuplicateOf: { submissionId: 's1', ownedByThisUser: true },
    });
    expect(own.blocksAutomatedApproval).toBe(true);
    expect(own.findings.find((f) => f.code === 'exact_duplicate')?.detail).toContain('already submitted');

    const stolen = buildForensicsReport({
      ...base,
      exactDuplicateOf: { submissionId: 's2', ownedByThisUser: false },
    });
    expect(stolen.findings.find((f) => f.code === 'exact_duplicate')?.detail).toContain("another user's");
  });

  // Bsheel's feed is public, so approved proof is a supply of stealable
  // images. Copying someone else's is a different act from re-saving your
  // own, and the weights say so.
  it('weighs a near-duplicate of another user above one of your own', () => {
    const own = buildForensicsReport({
      ...base,
      nearDuplicateOf: { submissionId: 's1', distance: 3, ownedByThisUser: true },
    });
    const stolen = buildForensicsReport({
      ...base,
      nearDuplicateOf: { submissionId: 's2', distance: 3, ownedByThisUser: false },
    });
    expect(own.findings.find((f) => f.code === 'near_duplicate')?.weight).toBe('strong');
    expect(stolen.findings.find((f) => f.code === 'near_duplicate')?.weight).toBe('decisive');
    expect(own.blocksAutomatedApproval).toBe(false);
    expect(stolen.blocksAutomatedApproval).toBe(true);
  });

  it('blocks approval on declared generated content', () => {
    const report = buildForensicsReport({
      ...base,
      exif: { ...base.exif, software: 'Midjourney v7' },
    });
    expect(report.blocksAutomatedApproval).toBe(true);
    expect(report.findings.map((f) => f.code)).toContain('generated_content_declared');
  });

  // A photograph can share a screen's dimensions by coincidence; it cannot
  // do that *and* carry no camera tags. Requiring both keeps the strong
  // finding off honest high-resolution photos.
  it('only calls screen dimensions suspicious when camera metadata is absent too', () => {
    const withCamera = codes({
      ...base,
      image: { width: 1179, height: 2556, format: 'jpeg' },
    });
    expect(withCamera).not.toContain('screen_dimensions');

    const withoutCamera = codes({
      ...base,
      exif: { capturedAtHasOffset: false, hasGps: false },
      image: { width: 1179, height: 2556, format: 'png' },
    });
    expect(withoutCamera).toContain('screen_dimensions');
  });

  // A screenshot is not proof of fraud — for `social` quests a call-log
  // screenshot is an honest attempt. It must inform a reviewer without
  // silently becoming a rejection.
  it('does not block approval on a screenshot alone', () => {
    const report = buildForensicsReport({
      ...base,
      exif: { capturedAtHasOffset: false, hasGps: false },
      image: { width: 1179, height: 2556, format: 'png' },
    });
    expect(report.blocksAutomatedApproval).toBe(false);
  });

  it('reports missing metadata as weak rather than damning', () => {
    const report = buildForensicsReport({ ...base, exif: noExif });
    const weights = report.findings.map((f) => f.weight);
    expect(weights).not.toContain('decisive');
    expect(report.findings.map((f) => f.code)).toEqual(
      expect.arrayContaining(['no_capture_time', 'no_camera_metadata']),
    );
  });
});
