import { createCipheriv, createDecipheriv, createHash, randomBytes } from 'node:crypto';
import { Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import type { Environment } from '../../../config/environment.js';

@Injectable()
export class DeviceTokenCipher {
  private readonly key: Buffer;

  constructor(config: ConfigService<Environment, true>) {
    this.key = createHash('sha256')
      .update(config.get('DEVICE_TOKEN_ENCRYPTION_KEY', { infer: true }), 'utf8')
      .digest();
  }

  protect(token: string): { hash: Buffer; encrypted: Buffer } {
    const iv = randomBytes(12);
    const cipher = createCipheriv('aes-256-gcm', this.key, iv);
    const ciphertext = Buffer.concat([cipher.update(token, 'utf8'), cipher.final()]);
    return {
      hash: createHash('sha256').update(token, 'utf8').digest(),
      encrypted: Buffer.concat([iv, cipher.getAuthTag(), ciphertext]),
    };
  }

  unprotect(encrypted: Buffer): string {
    if (encrypted.length < 29) throw new Error('Encrypted device token is malformed');
    const decipher = createDecipheriv('aes-256-gcm', this.key, encrypted.subarray(0, 12));
    decipher.setAuthTag(encrypted.subarray(12, 28));
    return Buffer.concat([
      decipher.update(encrypted.subarray(28)),
      decipher.final(),
    ]).toString('utf8');
  }
}
