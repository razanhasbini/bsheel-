import { spawn } from 'node:child_process';
import { mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { Processor, WorkerHost } from '@nestjs/bullmq';
import { Injectable, Logger } from '@nestjs/common';
import type { Job } from 'bullmq';
import { BrandedExportRepository, type BrandedExportSource } from './branded-export.repository.js';
import { ObjectStorageService } from './object-storage.service.js';

/// The band's proportions and colours — the same Arcade Pop band the app
/// composites under photos (`branded_media.dart`), so a shared video and a
/// shared photo from the same post look like siblings.
export const BAND = {
  /// Band height as a fraction of the video's height.
  heightFraction: 0.2,
  cream: '0xFFF9EE',
  ink: '0x1A1330',
  dim: '0x4A4458',
  /// Longest input the worker will transcode. A share is a clip, not an
  /// archive, and every extra second is CPU on the one worker.
  maxSeconds: 90,
  /// Largest original we will pull into memory for the render.
  maxInputBytes: 80 * 1024 * 1024,
  timeoutMs: 180_000,
} as const;

export interface BandText {
  readonly wordmark: string;
  /// One or two lines; the second only when the title needed it.
  readonly titleLines: readonly string[];
  readonly meta: string;
  /// Font sizes in pixels, bounded by the band AND the width, so a tall
  /// portrait clip does not get a title wider than the frame.
  readonly sizes: { readonly wordmark: number; readonly title: number; readonly meta: number };
}

/// The lines the band carries, sized and wrapped to the video so they never
/// run off it. drawtext does not wrap, so the wrapping and the clipping are
/// done here — and are the part worth a test.
export function bandText(source: BrandedExportSource, videoWidth: number, bandHeight: number): BandText {
  const sizes = {
    wordmark: Math.round(Math.min(bandHeight * 0.2, videoWidth * 0.045)),
    title: Math.round(Math.min(bandHeight * 0.2, videoWidth * 0.05)),
    meta: Math.round(Math.min(bandHeight * 0.13, videoWidth * 0.032)),
  };
  // ~0.55 em average glyph width for the brand sans; 9% side margins.
  const perLine = Math.max(8, Math.floor((videoWidth * 0.91) / (sizes.title * 0.55)));
  const titleLines = wrapWords(source.questTitle.trim(), perLine, 2);
  const when = source.submittedAt.toISOString().slice(0, 10);
  const where = source.placeName ?? source.countryName;
  const meta = [`@${source.username}`, when, where].filter((part): part is string => Boolean(part)).join('  ·  ');
  return { wordmark: 'BSHEEL', titleLines, meta, sizes };
}

/// Greedy word wrap into at most `maxLines`, clipping the last with an
/// ellipsis when the text does not fit.
export function wrapWords(text: string, perLine: number, maxLines: number): string[] {
  const lines: string[] = [];
  let current = '';
  for (const word of text.split(/\s+/).filter(Boolean)) {
    const candidate = current ? `${current} ${word}` : word;
    if (candidate.length <= perLine) {
      current = candidate;
      continue;
    }
    if (current) lines.push(current);
    current = word;
    if (lines.length === maxLines) break;
  }
  if (lines.length < maxLines && current) lines.push(current);
  const fitted = lines.slice(0, maxLines);
  const consumed = fitted.join(' ').length;
  const last = fitted[fitted.length - 1] ?? '';
  if (consumed < text.length || last.length > perLine) {
    fitted[fitted.length - 1] = `${last.slice(0, Math.max(1, perLine - 1)).trimEnd()}…`;
  }
  return fitted;
}

/**
 * Renders a post's video with the Bsheel band burned in (0050).
 *
 * Download the original, run one ffmpeg pass that pads the frame with a
 * cream band and draws the wordmark, quest title and "@who · date · where"
 * into it, upload the result beside the original, mark the row ready. Any
 * failure marks the row failed with a reason a person can read — the app
 * offers to try again, and the unbranded original is always still there.
 *
 * No BullMQ retries on purpose: a render that failed once will fail again
 * for the same input, and a transcode is the most expensive thing this
 * worker does.
 */
@Injectable()
@Processor('branded-export', { concurrency: 1 })
export class BrandedExportProcessor extends WorkerHost {
  private readonly logger = new Logger(BrandedExportProcessor.name);

  constructor(
    private readonly exports: BrandedExportRepository,
    private readonly storage: ObjectStorageService,
  ) {
    super();
  }

  async process(job: Job<{ exportId: string; submissionId: string }>): Promise<void> {
    const { exportId, submissionId } = job.data;
    if (!(await this.exports.markRendering(exportId))) {
      this.logger.debug({ exportId }, 'Branded export already rendering or done; nothing to do');
      return;
    }
    const record = await this.exports.find(submissionId);
    if (!record) return;
    // The requester already passed the visibility check when the row was
    // created; the read is repeated as them so a post taken down since
    // then is not rendered.
    const source = await this.exports.source(record.requested_by, submissionId);
    if (!source) {
      await this.exports.markFailed(exportId, 'The post is no longer available.');
      return;
    }

    const directory = await mkdtemp(join(tmpdir(), 'bsheel-brand-'));
    try {
      const key = firstMediaKey(source.mediaKey);
      const original = await this.storage.read(key, BAND.maxInputBytes);
      if (!original) throw new Error('The original video is too large to render.');
      const input = join(directory, 'in.mp4');
      const output = join(directory, 'out.mp4');
      await writeFile(input, original.body);

      const { width, height } = await this.probe(input);
      const band = Math.max(64, Math.round((height * BAND.heightFraction) / 2) * 2);
      const text = bandText(source, width, band);
      const files = {
        wordmark: join(directory, 'wordmark.txt'),
        titles: text.titleLines.map((_, index) => join(directory, `title-${index}.txt`)),
        meta: join(directory, 'meta.txt'),
      };
      await Promise.all([
        writeFile(files.wordmark, text.wordmark),
        ...text.titleLines.map((line, index) => writeFile(files.titles[index], line)),
        writeFile(files.meta, text.meta),
      ]);
      const fonts = {
        display: join(process.cwd(), 'assets/fonts/Syne-ExtraBold.ttf'),
        body: join(process.cwd(), 'assets/fonts/DMSans-SemiBold.ttf'),
        light: join(process.cwd(), 'assets/fonts/DMSans-Regular.ttf'),
      };
      // Vertical rhythm inside the band, as fractions of its height: the
      // wordmark on top, the title (one or two lines) in the middle, the
      // who/when/where line along the bottom.
      const x = 'w*0.045';
      const top = (fraction: number) => `h-${band}+${Math.round(band * fraction)}`;
      const titleTops = text.titleLines.length === 2 ? [0.3, 0.52] : [0.38];
      const filter = [
        'scale=trunc(iw/2)*2:trunc(ih/2)*2',
        `pad=w=iw:h=ih+${band}:x=0:y=0:color=${BAND.cream}`,
        `drawbox=x=0:y=ih-${band}:w=iw:h=4:color=${BAND.ink}:t=fill`,
        `drawtext=fontfile=${fonts.display}:textfile=${files.wordmark}:fontcolor=${BAND.ink}:fontsize=${text.sizes.wordmark}:x=${x}:y=${top(0.08)}`,
        ...text.titleLines.map((_, index) =>
          `drawtext=fontfile=${fonts.body}:textfile=${files.titles[index]}:fontcolor=${BAND.ink}:fontsize=${text.sizes.title}:x=${x}:y=${top(titleTops[index])}`),
        `drawtext=fontfile=${fonts.light}:textfile=${files.meta}:fontcolor=${BAND.dim}:fontsize=${text.sizes.meta}:x=${x}:y=${top(0.78)}`,
      ].join(',');

      await this.run('ffmpeg', [
        '-y', '-hide_banner', '-loglevel', 'error',
        '-i', input,
        '-t', String(BAND.maxSeconds),
        '-vf', filter,
        '-c:v', 'libx264', '-preset', 'veryfast', '-crf', '23', '-pix_fmt', 'yuv420p',
        '-c:a', 'aac', '-b:a', '128k',
        '-movflags', '+faststart',
        output,
      ], BAND.timeoutMs);

      const rendered = await readFile(output);
      const objectKey = `exports/${submissionId}/branded.mp4`;
      await this.storage.putObject(objectKey, rendered, 'video/mp4');
      await this.exports.markReady(exportId, objectKey);
      this.logger.log({ exportId, submissionId, bytes: rendered.length, width, height, band }, 'Branded export rendered');
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Render failed';
      this.logger.warn({ exportId, submissionId, message }, 'Branded export failed');
      await this.exports.markFailed(exportId, message);
    } finally {
      await rm(directory, { recursive: true, force: true });
    }
  }

  private async probe(input: string): Promise<{ width: number; height: number }> {
    const out = await this.run('ffprobe', [
      '-v', 'error', '-select_streams', 'v:0',
      '-show_entries', 'stream=width,height', '-of', 'csv=p=0', input,
    ], 20_000);
    const [w, h] = out.trim().split(/[,\n]/).map(Number);
    if (!w || !h) throw new Error('Could not read the video dimensions.');
    return { width: w, height: h };
  }

  private run(command: string, args: string[], timeoutMs: number): Promise<string> {
    return new Promise((resolve, reject) => {
      const child = spawn(command, args, { stdio: ['ignore', 'pipe', 'pipe'] });
      let stdout = '';
      let stderr = '';
      const timer = setTimeout(() => {
        child.kill('SIGKILL');
        reject(new Error(`${command} took longer than ${Math.round(timeoutMs / 1000)}s`));
      }, timeoutMs);
      child.stdout.on('data', (chunk: Buffer) => { stdout += chunk.toString(); });
      child.stderr.on('data', (chunk: Buffer) => { stderr += chunk.toString(); });
      child.on('error', (error) => { clearTimeout(timer); reject(error); });
      child.on('close', (code) => {
        clearTimeout(timer);
        if (code === 0) resolve(stdout);
        else reject(new Error(`${command} exited ${code}: ${stderr.trim().split('\n').pop() ?? ''}`.trim()));
      });
    });
  }
}

/// A submission with several files stores a JSON array of keys in
/// media_url; the video is the first entry either way.
export function firstMediaKey(mediaUrl: string): string {
  if (!mediaUrl.startsWith('[')) return mediaUrl;
  try {
    const parsed = JSON.parse(mediaUrl) as unknown;
    if (Array.isArray(parsed) && typeof parsed[0] === 'string') return parsed[0];
  } catch {
    // fall through
  }
  return mediaUrl;
}
