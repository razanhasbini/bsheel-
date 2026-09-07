export declare class CreateUploadIntentDto {
    clientRequestId: string;
    kind: 'avatar' | 'submission';
    contentType: string;
    sizeBytes: number;
}
export declare class CompleteUploadDto {
    objectId: string;
}
export declare class SignMediaDto {
    urls: string[];
}
export declare class DeleteMediaObjectDto {
    key: string;
}
