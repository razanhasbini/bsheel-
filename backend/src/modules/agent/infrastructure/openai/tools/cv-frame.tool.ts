import { tool } from '@openai/agents';
import { z } from 'zod';
import type { CvEvidenceProvider } from '../../../domain/cv-evidence.port.js';

/**
 * Lets the model ask for one of the opaque frame references CV evidence
 * already returned (never an arbitrary URL or path). Only useful once a CV
 * provider implements `getFrame`; the fail-closed default does not, so this
 * tool simply reports unavailable until then.
 */
export function buildCvFrameTool(provider: CvEvidenceProvider) {
  return tool({
    name: 'get_cv_key_frame',
    description: "Fetch one of the key frames already identified by the computer-vision analysis, by the opaque frameRef it returned. Use this only when a specific frame's visual detail would change your decision.",
    parameters: z.object({ frameRef: z.string() }),
    execute: async ({ frameRef }) => {
      if (!provider.getFrame) return { available: false as const };
      const frame = await provider.getFrame(frameRef);
      // Returns metadata only for now. Feeding the actual image bytes back
      // into the model's turn as a vision input needs the SDK's structured
      // tool-output image content type — a follow-up once a CV provider
      // that implements getFrame() actually exists to test it against.
      return { available: true as const, contentType: frame.contentType, sizeBytes: frame.bytes.byteLength };
    },
  });
}
