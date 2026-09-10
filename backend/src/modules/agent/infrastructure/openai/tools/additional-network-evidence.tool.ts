import { tool } from '@openai/agents';
import { z } from 'zod';
import type { LocationEvidenceQuery, NetworkEvidenceProvider } from '../../../domain/network-evidence.port.js';

/**
 * The agent's only network-evidence tool. The three mandatory capabilities
 * are gathered by the backend before the model ever runs (never gated
 * behind a tool call, because they are not optional) — this tool is only
 * for the *one additional* capability the agent may request afterward, and
 * only from the server-confirmed allowlist. The model supplies nothing but
 * the capability name; every identifying field (user, quest, place, time
 * window) is closed over server-side.
 */
export function buildAdditionalNetworkEvidenceTool(
  provider: NetworkEvidenceProvider,
  query: LocationEvidenceQuery,
  allowedCapabilities: readonly string[],
) {
  return tool({
    name: 'get_additional_network_evidence',
    description:
      'Request ONE additional CAMARA network signal beyond the mandatory baseline (Location Verification, Location Retrieval, Geofencing), when the baseline is missing, stale, or contradicts the submission. Only call this for a capability actually listed as allowed.',
    parameters: z.object({
      capability: z.enum(allowedCapabilities.length > 0 ? (allowedCapabilities as [string, ...string[]]) : ['NONE_AVAILABLE']),
    }),
    execute: async ({ capability }) => {
      if (!allowedCapabilities.includes(capability)) {
        return { outcome: 'UNAVAILABLE', reason: 'Capability not enabled for this deployment' };
      }
      return provider.getAdditionalEvidence(query, capability);
    },
  });
}
