import { Injectable } from '@nestjs/common';
import { ObjectStorageService } from '../../media/infrastructure/object-storage.service.js';
import { AccountRepository } from '../infrastructure/account.repository.js';

@Injectable()
export class AccountService {
  constructor(
    private readonly repository: AccountRepository,
    private readonly storage: ObjectStorageService,
  ) {}
  requestExport(userId: string) { return this.repository.requestExport(userId); }
  async exports(userId: string) {
    const rows = await this.repository.exports(userId);
    return Promise.all(rows.map(async (row) => ({
      ...row,
      download_url: typeof row.object_key === 'string' && row.status === 'ready'
        ? await this.storage.presignDownload(row.object_key)
        : null,
    })));
  }
  requestDeletion(userId: string) { return this.repository.requestDeletion(userId); }
}
