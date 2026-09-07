import type { AuthUser } from '../../../common/auth/auth-user.js';
import { MediaService } from '../application/media.service.js';
import { CompleteUploadDto, CreateUploadIntentDto, DeleteMediaObjectDto, SignMediaDto } from './media.dto.js';
declare class MediaIdParam {
    id: string;
}
export declare class MediaController {
    private readonly service;
    constructor(service: MediaService);
    createIntent(user: AuthUser, body: CreateUploadIntentDto): Promise<{
        objectId: string;
        key: string;
        uploadUrl: string;
        headers: {
            'content-type': string;
            'content-length': string;
        };
        expiresAt: string;
        status: "ready" | "pending";
    }>;
    complete(user: AuthUser, body: CompleteUploadDto): Promise<{
        id: string;
        key: string;
        status: "ready" | "deleted" | "pending" | "rejected";
    }>;
    sign(body: SignMediaDto): Promise<{
        urls: {
            [k: string]: string;
        };
    }>;
    deleteByKey(user: AuthUser, body: DeleteMediaObjectDto): Promise<void>;
    delete(user: AuthUser, param: MediaIdParam): Promise<void>;
}
export {};
