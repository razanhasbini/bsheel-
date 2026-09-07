export interface ApiResponse<T> {
  readonly success: true;
  readonly data: T;
  readonly meta: {
    readonly requestId: string;
    readonly timestamp: string;
  };
}

export interface ApiErrorResponse {
  readonly success: false;
  readonly error: {
    readonly code: string;
    readonly message: string;
    readonly details?: unknown;
  };
  readonly meta: {
    readonly requestId: string;
    readonly timestamp: string;
  };
}

