export declare class NotificationListQueryDto {
    limit: number;
    cursor?: string;
}
export declare class RegisterDeviceTokenDto {
    token: string;
    platform: 'ios' | 'android' | 'web';
}
export declare class DeleteDeviceTokenDto {
    token: string;
}
