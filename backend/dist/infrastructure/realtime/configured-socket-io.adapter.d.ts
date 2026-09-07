import type { INestApplicationContext } from '@nestjs/common';
import { IoAdapter } from '@nestjs/platform-socket.io';
import type { ServerOptions } from 'socket.io';
export declare class ConfiguredSocketIoAdapter extends IoAdapter {
    private readonly allowedOrigins;
    constructor(application: INestApplicationContext, allowedOrigins: readonly string[]);
    createIOServer(port: number, options?: ServerOptions): any;
}
