import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { spawn } from 'node:child_process';
import { mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import type { Environment } from '../../../config/environment.js';

/// Turns a video submission into still frames the vision models can read
/// (#47).
///
/// The vision APIs accept images, not video. Before this existed a video
/// submission was escalated as "could not be examined", which was honest but
/// meant every video went to a human — and video is the *harder* proof to
/// fake, so it was the format being penalised for being better.
///
/// Frames are sampled evenly across the duration rather than taken from the
/// start. The opening frame of a real clip is very often a blur or a floor,
/// and judging proof on it would reject honest players for holding their
/// phone badly for a quarter of a second.
///
/// ffmpeg is invoked directly rather than through a wrapper library: this is
/// one command with fixed arguments, and a wrapper would add a dependency
/// without removing any of the parts that actually need care — the timeout,
/// the temp-file cleanup, and behaving sanely when the binary is absent.
@Injectable()
export class VideoFrameExtractor {
  private readonly logger = new Logger(VideoFrameExtractor.name);
  private available?: boolean;

  constructor(private readonly config: ConfigService<Environment, true>) {}

  /// Whether ffmpeg is usable in this deployment.
  ///
  /// Probed once and cached. A deployment without it degrades to the previous
  /// behaviour — video escalates to a human — rather than failing every video
  /// submission, which is why this is a capability check and not a boot
  /// requirement.
  async isAvailable(): Promise<boolean> {
    if (this.available !== undefined) return this.available;
    this.available = await this.run('ffmpeg', ['-version'], 5_000)
      .then(() => true)
      .catch(() => false);
    if (!this.available) {
      this.logger.warn('ffmpeg is not available; video proof will be escalated to a human');
    }
    return this.available;
  }

  /// Extracts evenly-spaced JPEG frames, or an empty array if it cannot.
  ///
  /// Empty is an ordinary outcome — no ffmpeg, an unreadable container, a
  /// stream with no video track — and the caller reports the video as
  /// unexamined rather than guessing a verdict from it.
  async extract(video: Buffer): Promise<Buffer[]> {
    if (!(await this.isAvailable())) return [];

    const wanted = this.config.get('AI_VERIFICATION_VIDEO_FRAMES', { infer: true });
    const timeout = this.config.get('AI_VERIFICATION_FFMPEG_TIMEOUT_MS', { infer: true });
    const directory = await mkdtemp(join(tmpdir(), 'bsheel-frames-'));
    const source = join(directory, 'source');

    try {
      await writeFile(source, video);
      const duration = await this.duration(source, timeout);

      // A clip too short to sample across, or one whose duration ffprobe
      // could not read, still yields one frame — better than nothing.
      const timestamps = duration > 1
        ? Array.from({ length: wanted }, (_, index) => (duration * (index + 1)) / (wanted + 1))
        : [0];

      const frames: Buffer[] = [];
      for (const [index, at] of timestamps.entries()) {
        const output = join(directory, `frame-${index}.jpg`);
        try {
          await this.run(
            'ffmpeg',
            [
              // -ss before -i seeks by keyframe, which is far cheaper than
              // decoding up to the timestamp and is accurate enough for
              // sampling.
              '-ss', at.toFixed(3),
              '-i', source,
              '-frames:v', '1',
              // Cap the long edge. A 4K frame would blow past the vision
              // input limit and cost a fortune in tokens for detail no
              // verdict turns on.
              '-vf', "scale='min(1280,iw)':-2",
              '-q:v', '4',
              '-y', output,
            ],
            timeout,
          );
          frames.push(await readFile(output));
        } catch (error) {
          // One unreadable timestamp must not lose the frames that did
          // decode — a truncated upload often has a good first half.
          this.logger.debug(
            { at, err: error instanceof Error ? error.message : String(error) },
            'Could not extract a frame at this timestamp',
          );
        }
      }
      return frames;
    } catch (error) {
      this.logger.debug(
        { err: error instanceof Error ? error.message : String(error) },
        'Video frame extraction failed',
      );
      return [];
    } finally {
      // The worker is long-lived, so a leaked temp directory per video would
      // fill the disk rather than being cleaned up by process exit.
      await rm(directory, { recursive: true, force: true }).catch(() => undefined);
    }
  }

  /// One frame to show instead of the video, or null if it cannot be cut.
  ///
  /// Deliberately not `extract()[0]`. That samples evenly across the clip for
  /// a vision model, which wants the *representative* frames; a poster wants
  /// the frame a person would accept as a picture of this video, and it is
  /// sized for a map tile rather than for a model's input budget.
  ///
  /// It seeks a little way in rather than to 0: the first frame of a
  /// hand-held clip is very often the black or motion-blurred instant the
  /// camera started, which is worse than the category tint it replaces. A
  /// tenth of the way in, capped at two seconds, lands on the shot.
  async poster(video: Buffer, maxEdge = 640): Promise<Buffer | null> {
    if (!(await this.isAvailable())) return null;

    const timeout = this.config.get('AI_VERIFICATION_FFMPEG_TIMEOUT_MS', { infer: true });
    const directory = await mkdtemp(join(tmpdir(), 'bsheel-poster-'));
    const source = join(directory, 'source');
    const output = join(directory, 'poster.jpg');
    try {
      await writeFile(source, video);
      const duration = await this.duration(source, timeout);
      const at = duration > 0 ? Math.min(duration / 10, 2) : 0;
      await this.run(
        'ffmpeg',
        [
          '-ss', at.toFixed(3),
          '-i', source,
          '-frames:v', '1',
          '-vf', `scale='min(${maxEdge},iw)':-2`,
          '-q:v', '5',
          '-y', output,
        ],
        timeout,
      );
      return await readFile(output);
    } catch (error) {
      this.logger.debug(
        { err: error instanceof Error ? error.message : String(error) },
        'Could not cut a poster frame',
      );
      return null;
    } finally {
      await rm(directory, { recursive: true, force: true }).catch(() => undefined);
    }
  }

  /// Duration in seconds, or 0 when ffprobe cannot say.
  private async duration(path: string, timeout: number): Promise<number> {
    try {
      const output = await this.run(
        'ffprobe',
        ['-v', 'error', '-show_entries', 'format=duration', '-of', 'csv=p=0', path],
        timeout,
      );
      const seconds = Number.parseFloat(output.trim());
      return Number.isFinite(seconds) && seconds > 0 ? seconds : 0;
    } catch {
      return 0;
    }
  }

  /// Runs a binary with a hard timeout, rejecting on a non-zero exit.
  ///
  /// The timeout is the point: ffmpeg on a malformed file can spin, and this
  /// runs inside a queue worker where one wedged process would stall every
  /// submission behind it.
  private run(command: string, args: readonly string[], timeoutMs: number): Promise<string> {
    return new Promise((resolve, reject) => {
      const child = spawn(command, [...args], { stdio: ['ignore', 'pipe', 'pipe'] });
      let stdout = '';
      let stderr = '';
      const timer = setTimeout(() => {
        child.kill('SIGKILL');
        reject(new Error(`${command} timed out after ${timeoutMs}ms`));
      }, timeoutMs);
      timer.unref();

      child.stdout.on('data', (chunk: Buffer) => { stdout += chunk.toString(); });
      // Captured but not logged wholesale: ffmpeg writes its banner to
      // stderr on every run, so treating it as an error signal would be
      // noise. Only the exit code decides.
      child.stderr.on('data', (chunk: Buffer) => { stderr += chunk.toString(); });
      child.on('error', (error) => { clearTimeout(timer); reject(error); });
      child.on('close', (code) => {
        clearTimeout(timer);
        if (code === 0) resolve(stdout);
        else reject(new Error(`${command} exited ${code}: ${stderr.slice(-500)}`));
      });
    });
  }
}
