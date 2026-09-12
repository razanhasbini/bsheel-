/**
 * Keep provider credentials and request headers out of application logs.
 * SDK error objects may retain the entire request/response, so callers must
 * log this deliberately small descriptor instead of serialising `error`.
 */
export function describeCamaraError(error: unknown): {
  readonly name: string;
  readonly status?: number;
  readonly code?: string;
  readonly detail?: string;
} {
  const candidate = error as {
    name?: unknown;
    status?: unknown;
    statusCode?: unknown;
    code?: unknown;
    body?: unknown;
  } | null;
  const status = typeof candidate?.statusCode === 'number'
    ? candidate.statusCode
    : typeof candidate?.status === 'number'
      ? candidate.status
      : undefined;
  const detail = problemDetail(candidate?.body);
  return {
    name: typeof candidate?.name === 'string' ? candidate.name : 'ProviderError',
    ...(status === undefined ? {} : { status }),
    ...(typeof candidate?.code === 'string' ? { code: candidate.code.slice(0, 80) } : {}),
    ...(detail === undefined ? {} : { detail }),
  };
}

/**
 * The one field of an error body worth keeping.
 *
 * CAMARA errors are problem-details objects, and the human-readable half is
 * the whole diagnosis: Nokia answers geofencing with 404 `Target not found`
 * for a device the network does not know, which is a completely different
 * fact from the 404 a wrong `x-rapidapi-host` produces. Without this, both
 * arrive as "HTTP 404" and the wrong one gets fixed.
 *
 * Only the short string is taken, never the object — an SDK error body can
 * carry the echoed request, and that request contains a sink credential.
 */
function problemDetail(body: unknown): string | undefined {
  if (typeof body === 'string') return body.slice(0, 200);
  if (body === null || typeof body !== 'object') return undefined;
  const record = body as { detail?: unknown; message?: unknown; status?: unknown };
  const text = typeof record.detail === 'string'
    ? record.detail
    : typeof record.message === 'string'
      ? record.message
      : undefined;
  return text?.slice(0, 200);
}
