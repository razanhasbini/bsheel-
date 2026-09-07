var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
var __metadata = (this && this.__metadata) || function (k, v) {
    if (typeof Reflect === "object" && typeof Reflect.metadata === "function") return Reflect.metadata(k, v);
};
import { createCipheriv, createDecipheriv, createHash, randomBytes } from 'node:crypto';
import { Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
let DeviceTokenCipher = class DeviceTokenCipher {
    key;
    constructor(config) {
        this.key = createHash('sha256')
            .update(config.get('DEVICE_TOKEN_ENCRYPTION_KEY', { infer: true }), 'utf8')
            .digest();
    }
    protect(token) {
        const iv = randomBytes(12);
        const cipher = createCipheriv('aes-256-gcm', this.key, iv);
        const ciphertext = Buffer.concat([cipher.update(token, 'utf8'), cipher.final()]);
        return {
            hash: createHash('sha256').update(token, 'utf8').digest(),
            encrypted: Buffer.concat([iv, cipher.getAuthTag(), ciphertext]),
        };
    }
    unprotect(encrypted) {
        if (encrypted.length < 29)
            throw new Error('Encrypted device token is malformed');
        const decipher = createDecipheriv('aes-256-gcm', this.key, encrypted.subarray(0, 12));
        decipher.setAuthTag(encrypted.subarray(12, 28));
        return Buffer.concat([
            decipher.update(encrypted.subarray(28)),
            decipher.final(),
        ]).toString('utf8');
    }
};
DeviceTokenCipher = __decorate([
    Injectable(),
    __metadata("design:paramtypes", [ConfigService])
], DeviceTokenCipher);
export { DeviceTokenCipher };
//# sourceMappingURL=device-token-cipher.js.map