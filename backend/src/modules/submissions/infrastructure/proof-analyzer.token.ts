/// DI token for the vision provider (#47).
///
/// A token rather than a concrete class, so the cascade depends on the
/// `ProofAnalyzer` interface and the provider is chosen once, in the module,
/// from `AI_VERIFICATION_PROVIDER`. That is what lets the eval score both
/// providers over the same labelled history without touching the pipeline.
export const PROOF_ANALYZER = Symbol('PROOF_ANALYZER');
