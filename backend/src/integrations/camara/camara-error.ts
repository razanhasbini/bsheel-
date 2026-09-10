/**
 * Keep provider credentials and request headers out of application logs.
 * SDK error objects may retain the entire request/response, so callers must
 * log this deliberately small descriptor instead of serialising `error`.
 */
export function describeCamaraError(error: unknown): {
  readonly name: string;
  readonly status?: number;
  readonly code?: string;
} {
  const candidate = error as {
    name?: unknown;
    status?: unknown;
    statusCode?: unknown;
    code?: unknown;
  } | null;
  const status = typeof candidate?.statusCode === 'number'
    ? candidate.statusCode
    : typeof candidate?.status === 'number'
      ? candidate.status
      : undefined;
  return {
    name: typeof candidate?.name === 'string' ? candidate.name : 'ProviderError',
    ...(status === undefined ? {} : { status }),
    ...(typeof candidate?.code === 'string' ? { code: candidate.code.slice(0, 80) } : {}),
  };
}
