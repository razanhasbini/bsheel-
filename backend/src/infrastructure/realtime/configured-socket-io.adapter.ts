import type { INestApplicationContext } from '@nestjs/common';
import { IoAdapter } from '@nestjs/platform-socket.io';
import type { ServerOptions } from 'socket.io';

export class ConfiguredSocketIoAdapter extends IoAdapter {
  constructor(
    application: INestApplicationContext,
    private readonly allowedOrigins: readonly string[],
  ) {
    super(application);
  }

  override createIOServer(port: number, options?: ServerOptions) {
    return super.createIOServer(port, {
      ...options,
      cors: {
        origin: [...this.allowedOrigins],
        credentials: true,
      },
    });
  }
}
