import sharp from 'sharp';

/// Real image fixtures for proof forensics (#47).
///
/// These are genuine encoded JPEG/PNG bytes with genuine EXIF, produced at
/// test time rather than committed as binaries. The forensics code reads
/// pixels and metadata, so testing it against mocks would prove nothing about
/// whether it can actually read a photograph — and the seed script's 1x1 PNG
/// has no EXIF and an identical hash for every submission, which makes it
/// useless for duplicate or provenance testing.

/// A recognisable, non-uniform image, so a perceptual hash of it carries real
/// gradient structure. A flat colour would hash to all zeroes and every
/// comparison would be vacuously equal.
async function texturedBase(width = 640, height = 480): Promise<Buffer> {
  const channels = 3;
  const pixels = Buffer.alloc(width * height * channels);
  for (let y = 0; y < height; y += 1) {
    for (let x = 0; x < width; x += 1) {
      const offset = (y * width + x) * channels;
      // A diagonal gradient with a couple of blocks, giving both smooth
      // ramps and hard edges for the hash to bite on.
      const ramp = Math.floor((x / width) * 200 + (y / height) * 40);
      const block = x > width * 0.6 && y > height * 0.5 ? 70 : 0;
      pixels[offset] = Math.min(255, ramp + block);
      pixels[offset + 1] = Math.min(255, Math.floor(ramp * 0.7) + block);
      pixels[offset + 2] = Math.min(255, 255 - ramp);
    }
  }
  return sharp(pixels, { raw: { width, height, channels } }).jpeg({ quality: 92 }).toBuffer();
}

export interface ExifOptions {
  readonly capturedAt?: Date;
  readonly offsetTimeOriginal?: string;
  readonly cameraMake?: string;
  readonly cameraModel?: string;
  readonly software?: string;
}

/// EXIF DateTimeOriginal is `YYYY:MM:DD HH:MM:SS` local wall-clock, with no
/// zone — the format that makes the timezone tolerance in
/// classifyCaptureWindow necessary.
function exifDateTime(value: Date): string {
  const pad = (input: number): string => String(input).padStart(2, '0');
  return `${value.getUTCFullYear()}:${pad(value.getUTCMonth() + 1)}:${pad(value.getUTCDate())} `
    + `${pad(value.getUTCHours())}:${pad(value.getUTCMinutes())}:${pad(value.getUTCSeconds())}`;
}

/// A photograph as a phone would produce it: camera tags and a capture time.
export async function cameraPhoto(options: ExifOptions = {}): Promise<Buffer> {
  const base = await texturedBase();
  const ifd0: Record<string, string> = {};
  if (options.cameraMake ?? true) ifd0.Make = options.cameraMake ?? 'Apple';
  if (options.cameraModel ?? true) ifd0.Model = options.cameraModel ?? 'iPhone 17 Pro';
  if (options.software) ifd0.Software = options.software;

  const exif: Record<string, string> = {};
  if (options.capturedAt) {
    exif.DateTimeOriginal = exifDateTime(options.capturedAt);
    if (options.offsetTimeOriginal) exif.OffsetTimeOriginal = options.offsetTimeOriginal;
  }

  return sharp(base)
    .withExif({ IFD0: ifd0, ...(Object.keys(exif).length > 0 ? { IFD2: exif } : {}) })
    .jpeg({ quality: 92 })
    .toBuffer();
}

/// The same picture, re-encoded at lower quality and resized — the shape of
/// ordinary recycling, where a user re-saves or re-shares an image. Its
/// difference hash should stay close to the original's.
export async function reEncodedCopy(): Promise<Buffer> {
  const base = await texturedBase();
  return sharp(base).resize(512, 384).jpeg({ quality: 55 }).toBuffer();
}

/// A different picture, so the duplicate threshold has a genuine negative to
/// stay clear of.
export async function unrelatedPhoto(): Promise<Buffer> {
  const width = 640;
  const height = 480;
  const channels = 3;
  const pixels = Buffer.alloc(width * height * channels);
  for (let y = 0; y < height; y += 1) {
    for (let x = 0; x < width; x += 1) {
      const offset = (y * width + x) * channels;
      // Concentric rings: structurally unlike the diagonal ramp above.
      const distance = Math.hypot(x - width / 2, y - height / 2);
      const ring = Math.floor((Math.sin(distance / 12) + 1) * 110);
      pixels[offset] = ring;
      pixels[offset + 1] = 255 - ring;
      pixels[offset + 2] = Math.floor(ring * 0.4);
    }
  }
  return sharp(pixels, { raw: { width, height, channels } }).jpeg({ quality: 92 }).toBuffer();
}

/// A screenshot: exact device dimensions, PNG, and no camera metadata.
export async function screenshot(width = 1179, height = 2556): Promise<Buffer> {
  return sharp({
    create: { width, height, channels: 3, background: { r: 22, g: 22, b: 30 } },
  }).png().toBuffer();
}

/// The 9x8 grayscale bitmap a difference hash is computed from.
///
/// `fit: 'fill'` on purpose: the hash must describe the whole frame, and
/// preserving aspect ratio would letterbox and encode the padding instead.
export async function grayscale9x8(image: Buffer): Promise<Uint8Array> {
  const raw = await sharp(image)
    .resize(9, 8, { fit: 'fill' })
    .grayscale()
    .raw()
    .toBuffer();
  return new Uint8Array(raw);
}
