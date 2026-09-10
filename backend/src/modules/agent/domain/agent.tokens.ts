// DI tokens for the replaceable evidence ports. Bound in
// src/integrations/camara and src/integrations/computer-vision; the agent
// module depends only on these tokens, never on a concrete provider.
export const CV_EVIDENCE_PROVIDER = Symbol('CV_EVIDENCE_PROVIDER');
export const NETWORK_EVIDENCE_PROVIDER = Symbol('NETWORK_EVIDENCE_PROVIDER');
