/// Deterministic proof forensics (#47).
///
/// No model, no network, no cost. For the large part of Bsheel's catalogue
/// that content analysis cannot serve — "read 20 pages", "compliment a
/// stranger", "spend an hour with no phone" — this is the *entire* signal.
/// It is also the strongest signal where content *can* be judged, because a
/// photograph captured before the quest was assigned is recycled whatever it
/// happens to depict.
///
/// Everything here is a pure function of bytes and metadata, so it is unit
/// tested against real fixture images rather than mocked.

/// A 64-bit difference hash, as a string of '0'/'1' — the representation the
/// `pg` driver uses for `bit(64)`, so it round-trips without conversion and
/// Hamming distance is computed in SQL via `bit_count(a # b)`.
export type PerceptualHash = string;

export type CaptureWindow =
  /// Captured between assignment and submission. The honest case.
  | 'within_window'
  /// Captured before the quest was even assigned. Strong recycling evidence.
  | 'predates_assignment'
  /// Captured after it was submitted. Clock skew or tampering, not fraud
  /// evidence on its own — phone clocks are wrong more often than users lie.
  | 'after_submission'
  /// No usable capture time. Common and not incriminating by itself.
  | 'unknown';

export interface ExifFacts {
  /// EXIF DateTimeOriginal, if present.
  readonly capturedAt?: Date;
  /// True when the capture time carried a UTC offset, so the comparison
  /// below can be exact instead of tolerant.
  readonly capturedAtHasOffset: boolean;
  readonly cameraMake?: string;
  readonly cameraModel?: string;
  /// Editing software that touched the file, from the Software tag.
  readonly software?: string;
  readonly hasGps: boolean;
}

export interface ImageFacts {
  readonly width: number;
  readonly height: number;
  readonly format: string;
}

export interface ForensicFinding {
  readonly code: ForensicCode;
  /// How much this should move a reviewer, not how certain the measurement
  /// is. A finding can be certain and still weak evidence.
  readonly weight: 'info' | 'weak' | 'strong' | 'decisive';
  /// Written for the moderator who reads it in the queue.
  readonly detail: string;
}

export type ForensicCode =
  | 'capture_predates_assignment'
  | 'capture_after_submission'
  | 'no_capture_time'
  | 'no_camera_metadata'
  | 'screen_dimensions'
  | 'edited_by_software'
  | 'exact_duplicate'
  | 'near_duplicate'
  | 'generated_content_declared'
  | 'capture_within_window'
  | 'camera_metadata_present';

/// EXIF `DateTimeOriginal` is local wall-clock time with **no timezone**.
///
/// This is the trap that would make a naive implementation reject honest
/// users. A player in Beirut (UTC+3) photographing their quest at 09:00 local
/// writes "09:00" into EXIF; compared against a UTC `assigned_at` of 07:30
/// that reads as fine, but the same photo taken at 09:00 in Apia (UTC+13)
/// against an assignment made minutes earlier reads as *ten hours before the
/// quest existed*. Bsheel is explicitly a multi-region product — Lebanon and
/// Qatar are both seeded, and #51 adds cross-country quests.
///
/// So without a known offset the comparison is widened by the maximum real
/// UTC offset in both directions. That deliberately costs sensitivity: a
/// genuinely recycled photo from earlier the same day will read as
/// 'within_window'. Missing a lazy cheat is a far cheaper error than telling
/// a truthful player in the wrong timezone that they faked their proof.
const maxUtcOffsetMs = 14 * 60 * 60 * 1000;

/// Phone clocks drift and users submit immediately after shooting. A little
/// slack on the trailing edge stops that presenting as tampering.
const submissionGraceMs = 10 * 60 * 1000;

export function classifyCaptureWindow(
  exif: ExifFacts,
  assignedAt: Date,
  submittedAt: Date,
): CaptureWindow {
  if (!exif.capturedAt) return 'unknown';
  const captured = exif.capturedAt.getTime();
  const tolerance = exif.capturedAtHasOffset ? 0 : maxUtcOffsetMs;
  if (captured < assignedAt.getTime() - tolerance) return 'predates_assignment';
  if (captured > submittedAt.getTime() + tolerance + submissionGraceMs) return 'after_submission';
  return 'within_window';
}

/// Device screen resolutions, in the orientation-independent form.
///
/// A photograph is whatever size the sensor produced; an image whose
/// dimensions match a screen *exactly*, with no camera metadata, is a
/// screenshot or a photo of a display. Neither is proof of doing anything —
/// though for `social` quests a call-log screenshot is an honest attempt
/// rather than fraud, which is why this is a finding and not a verdict.
const screenResolutions: readonly (readonly [number, number])[] = [
  [1170, 2532], [1179, 2556], [1206, 2622], [1284, 2778], [1290, 2796], [1320, 2868],
  [1125, 2436], [1242, 2688], [828, 1792], [750, 1334], [640, 1136],
  [1080, 1920], [1080, 2340], [1080, 2400], [1440, 3120], [1440, 3200],
  [1668, 2388], [2048, 2732], [1620, 2160],
  [1920, 1080], [2560, 1440], [3840, 2160], [1366, 768], [1512, 982], [1728, 1117],
];

export function matchesScreenResolution(width: number, height: number): boolean {
  const [short, long] = width <= height ? [width, height] : [height, width];
  return screenResolutions.some(([w, h]) => w === short && h === long);
}

/// Software tags that indicate the pixels were composed rather than captured.
/// Distinct from ordinary editing: a crop or a filter is normal, and users
/// should not be punished for it.
const generativeSoftware = [
  'dall-e', 'midjourney', 'stable diffusion', 'firefly', 'imagen',
  'sora', 'flux', 'nano banana', 'grok-image', 'seedream',
];

export function declaresGeneratedContent(software: string | undefined): boolean {
  if (!software) return false;
  const value = software.toLowerCase();
  return generativeSoftware.some((marker) => value.includes(marker));
}

/// A 64-bit dHash from a 9x8 grayscale bitmap.
///
/// dHash compares each pixel with its right-hand neighbour, so it encodes
/// gradient structure rather than absolute brightness: re-encoding, resizing
/// and moderate recompression leave it nearly unchanged, which is what
/// catches the common recycling case of "same photo, saved again".
///
/// Its known limit, stated so nobody over-trusts it: a hard crop or a large
/// rotation moves it a long way, so a determined re-crop defeats it. That is
/// an argument for pairing it with exact-byte matching and content analysis,
/// not for reaching for something heavier — a DCT-based pHash has the same
/// weakness against crops.
/// Null when the hash would not distinguish this frame from any other.
///
/// This is the failure that makes a perceptual hash dangerous rather than
/// merely imprecise, and the rule is narrower than it first looks.
///
/// `differenceHash` records, for each of 64 positions, whether a pixel is
/// brighter than its right neighbour. If **every** comparison comes out the
/// same way the hash is 64 identical bits, and every other frame with that
/// property produces the identical hash — Hamming distance 0, far inside the
/// near-duplicate threshold (10 by default). Two frames are then recorded as
/// near duplicates of each other on the strength of a fingerprint that
/// describes neither, and a near duplicate not owned by this user is
/// weighted `decisive`: a measurement accusing an honest player of
/// submitting someone else's proof.
///
/// Two quite different pictures land there. A **flat** frame — a dark
/// screenshot, a white wall, a night sky — has no variation at all, so every
/// comparison is a tie and every tie reads '0'. But so does any **smooth
/// one-directional gradient**, a sky at dawn or a wall lit from one side,
/// however much dynamic range it has: brightness rises left to right
/// everywhere, so every comparison is '0' for a real reason rather than for
/// want of information. Testing the frame's *range* catches only the first
/// kind. Testing the hash for degeneracy catches both, and states the actual
/// hazard: a fingerprint every member of a large class shares is not a
/// fingerprint.
///
/// So such a frame gets no hash. `media_objects.perceptual_hash` is nullable
/// and `findDuplicate` already requires it to be non-null, so null cleanly
/// means "cannot be perceptually fingerprinted" rather than "matches
/// everything". Exact-byte matching is unaffected: identical bytes really are
/// the same file, whatever the picture looks like.
///
/// The fixtures have always known half of this — `proof-fixtures.ts` says a
/// flat colour "would hash to all zeroes and every comparison would be
/// vacuously equal" — but the knowledge lived in the helper that avoided the
/// problem rather than in the code that has to survive it.
export function differenceHash(grayscale9x8: Uint8Array): PerceptualHash | null {
  if (grayscale9x8.length !== 72) {
    throw new Error(`differenceHash expects a 9x8 grayscale bitmap (72 bytes), got ${grayscale9x8.length}`);
  }
  let bits = '';
  for (let row = 0; row < 8; row += 1) {
    for (let column = 0; column < 8; column += 1) {
      const left = grayscale9x8[row * 9 + column];
      const right = grayscale9x8[row * 9 + column + 1];
      bits += left > right ? '1' : '0';
    }
  }
  return bits.includes('0') && bits.includes('1') ? bits : null;
}

/// Hamming distance between two hashes.
///
/// Mirrors what Postgres computes as `bit_count(a # b)`; kept here so the
/// tests and the eval harness can measure distance without a database.
export function hammingDistance(left: PerceptualHash, right: PerceptualHash): number {
  if (left.length !== right.length) {
    throw new Error(`hash length mismatch: ${left.length} vs ${right.length}`);
  }
  let distance = 0;
  for (let index = 0; index < left.length; index += 1) {
    if (left[index] !== right[index]) distance += 1;
  }
  return distance;
}

/// Distance at or below which two images are treated as the same picture.
///
/// 10 of 64 bits. Chosen to sit above the drift caused by re-encoding and
/// resizing, and below the distance between genuinely different photographs;
/// it is a threshold to calibrate against the eval set, not a constant to
/// trust. Exposed so the eval harness can sweep it.
export const nearDuplicateThreshold = 10;

export function isNearDuplicate(
  left: PerceptualHash,
  right: PerceptualHash,
  threshold = nearDuplicateThreshold,
): boolean {
  return hammingDistance(left, right) <= threshold;
}

export interface ForensicsInput {
  readonly exif: ExifFacts;
  readonly image: ImageFacts;
  readonly assignedAt: Date;
  readonly submittedAt: Date;
  /// A prior submission with byte-identical content, if one exists.
  readonly exactDuplicateOf?: { submissionId: string; ownedByThisUser: boolean };
  /// The closest prior submission by perceptual hash, if within threshold.
  readonly nearDuplicateOf?: { submissionId: string; distance: number; ownedByThisUser: boolean };
}

export interface ForensicsReport {
  readonly captureWindow: CaptureWindow;
  readonly findings: readonly ForensicFinding[];
  /// True when something here should stop an automated approval outright,
  /// whatever the quest's contract or the content analysis says.
  readonly blocksAutomatedApproval: boolean;
}

/// Turns measured facts into findings a moderator can read and a policy can
/// act on.
///
/// Note what is *not* here: a score. Collapsing these into one number would
/// hide that "no capture time" and "byte-identical to a rejected submission"
/// are different kinds of thing, and the policy layer needs to treat them
/// differently. The findings stay separate and named.
export function buildForensicsReport(input: ForensicsInput): ForensicsReport {
  const findings: ForensicFinding[] = [];
  const captureWindow = classifyCaptureWindow(input.exif, input.assignedAt, input.submittedAt);

  if (captureWindow === 'predates_assignment') {
    findings.push({
      code: 'capture_predates_assignment',
      weight: 'decisive',
      detail: `The photograph's capture time is before this quest was assigned${
        input.exif.capturedAtHasOffset ? '' : ', by more than any timezone can explain'
      }. It cannot be proof of this attempt.`,
    });
  } else if (captureWindow === 'after_submission') {
    findings.push({
      code: 'capture_after_submission',
      weight: 'info',
      detail: 'The capture time is later than the submission time, which usually means a wrong device clock rather than anything deliberate.',
    });
  } else if (captureWindow === 'within_window') {
    findings.push({
      code: 'capture_within_window',
      weight: 'info',
      detail: 'The capture time falls between assignment and submission.',
    });
  } else {
    findings.push({
      code: 'no_capture_time',
      weight: 'weak',
      detail: 'No capture time in the file. Common for shared or re-saved images, and for screenshots.',
    });
  }

  if (declaresGeneratedContent(input.exif.software)) {
    findings.push({
      code: 'generated_content_declared',
      weight: 'decisive',
      detail: `The file declares it was produced by ${input.exif.software}. This is generated imagery, not a photograph of something done.`,
    });
  } else if (input.exif.software) {
    findings.push({
      code: 'edited_by_software',
      weight: 'info',
      detail: `Processed by ${input.exif.software}. Editing is normal and not itself suspicious.`,
    });
  }

  if (input.exif.cameraMake || input.exif.cameraModel) {
    findings.push({
      code: 'camera_metadata_present',
      weight: 'info',
      detail: `Camera metadata present (${[input.exif.cameraMake, input.exif.cameraModel].filter(Boolean).join(' ')}).`,
    });
  } else {
    findings.push({
      code: 'no_camera_metadata',
      weight: 'weak',
      detail: 'No camera make or model. Expected for screenshots, downloads and re-saved images.',
    });
  }

  // Only meaningful together: a real photograph can coincidentally match a
  // screen's aspect and size, but not while also carrying no camera tags.
  if (
    matchesScreenResolution(input.image.width, input.image.height)
    && !input.exif.cameraMake
    && !input.exif.cameraModel
  ) {
    findings.push({
      code: 'screen_dimensions',
      weight: 'strong',
      detail: `Dimensions (${input.image.width}x${input.image.height}) exactly match a device screen and there is no camera metadata, so this is very likely a screenshot or a photo of a display.`,
    });
  }

  if (input.exactDuplicateOf) {
    findings.push({
      code: 'exact_duplicate',
      weight: 'decisive',
      detail: input.exactDuplicateOf.ownedByThisUser
        ? 'Byte-identical to proof this user has already submitted.'
        : "Byte-identical to another user's submission, so it is not this user's own proof.",
    });
  } else if (input.nearDuplicateOf) {
    findings.push({
      code: 'near_duplicate',
      weight: input.nearDuplicateOf.ownedByThisUser ? 'strong' : 'decisive',
      detail: input.nearDuplicateOf.ownedByThisUser
        ? `Nearly identical to this user's earlier submission (distance ${input.nearDuplicateOf.distance}). Possibly the same photograph re-saved.`
        : `Nearly identical to another user's submission (distance ${input.nearDuplicateOf.distance}). Bsheel's feed is public, so approved proof can be copied from it.`,
    });
  }

  return {
    captureWindow,
    findings,
    blocksAutomatedApproval: findings.some((finding) => finding.weight === 'decisive'),
  };
}
