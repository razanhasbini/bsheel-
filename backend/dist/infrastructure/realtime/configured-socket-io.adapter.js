import { IoAdapter } from '@nestjs/platform-socket.io';
export class ConfiguredSocketIoAdapter extends IoAdapter {
    allowedOrigins;
    constructor(application, allowedOrigins) {
        super(application);
        this.allowedOrigins = allowedOrigins;
    }
    createIOServer(port, options) {
        return super.createIOServer(port, {
            ...options,
            cors: {
                origin: [...this.allowedOrigins],
                credentials: true,
            },
        });
    }
}
//# sourceMappingURL=configured-socket-io.adapter.js.map