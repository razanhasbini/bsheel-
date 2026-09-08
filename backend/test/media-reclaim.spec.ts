import { describe, expect, it, vi } from 'vitest';
import { MediaReclaimService } from '../src/modules/media/application/media-reclaim.service.js';
import type { MediaRepository } from '../src/modules/media/infrastructure/media.repository.js';
import type { ObjectStorageService } from '../src/modules/media/infrastructure/object-storage.service.js';

function setup(enabled = true) {
  const repository = {
    claimReclaimable: vi.fn(),
    markReclaimed: vi.fn().mockResolvedValue(0),
    releaseReclaim: vi.fn().mockResolvedValue(undefined),
  };
  const storage = { delete: vi.fn().mockResolvedValue(undefined) };
  const config = {
    get: vi.fn((key: string) => ({
      MEDIA_RECLAIM_ENABLED: enabled,
      MEDIA_RECLAIM_GRACE_HOURS: 24,
      MEDIA_RECLAIM_BATCH_SIZE: 200,
    } as Record<string, unknown>)[key]),
  };
  const service = new MediaReclaimService(
    repository as unknown as MediaRepository,
    storage as unknown as ObjectStorageService,
    config as never,
  );
  return { service, repository, storage, config };
}

describe('MediaReclaimService', () => {
  it('does not query or delete when reclaim is disabled', async () => {
    const { service, repository } = setup(false);
    await expect(service.sweep()).resolves.toEqual({ claimed: 0, deleted: 0, failed: 0, byReason: {} });
    expect(repository.claimReclaimable).not.toHaveBeenCalled();
  });

  it('deletes every candidate before marking its rows reclaimed', async () => {
    const { service, repository, storage } = setup();
    repository.claimReclaimable.mockResolvedValue([
      { id: 'abandoned', object_key: 'submissions/u/a.jpg', reason: 'abandoned_intent', reclaim_token: 'lease' },
      { id: 'rejected', object_key: 'submissions/u/b.jpg', reason: 'rejected_upload', reclaim_token: 'lease' },
      { id: 'avatar', object_key: 'avatars/u/c.jpg', reason: 'superseded_avatar', reclaim_token: 'lease' },
    ]);
    repository.markReclaimed.mockResolvedValue(3);

    await expect(service.sweep()).resolves.toEqual({
      claimed: 3,
      deleted: 3,
      failed: 0,
      byReason: { abandoned_intent: 1, rejected_upload: 1, superseded_avatar: 1 },
    });
    expect(repository.claimReclaimable).toHaveBeenCalledWith(24, 200);
    expect(storage.delete).toHaveBeenCalledTimes(3);
    expect(repository.markReclaimed).toHaveBeenCalledWith(await repository.claimReclaimable.mock.results[0].value);
  });

  it('leaves storage failures claimable for the next pass', async () => {
    const { service, repository, storage } = setup();
    repository.claimReclaimable.mockResolvedValue([
      { id: 'ok', object_key: 'avatars/u/ok.jpg', reason: 'superseded_avatar', reclaim_token: 'lease' },
      { id: 'failed', object_key: 'submissions/u/fail.jpg', reason: 'rejected_upload', reclaim_token: 'lease' },
    ]);
    storage.delete.mockImplementation(async (key: string) => {
      if (key.endsWith('fail.jpg')) throw new Error('storage unavailable');
    });
    repository.markReclaimed.mockResolvedValue(1);

    await expect(service.sweep()).resolves.toEqual({
      claimed: 2,
      deleted: 1,
      failed: 1,
      byReason: { superseded_avatar: 1 },
    });
    expect(repository.markReclaimed).toHaveBeenCalledWith([
      { id: 'ok', object_key: 'avatars/u/ok.jpg', reason: 'superseded_avatar', reclaim_token: 'lease' },
    ]);
    expect(repository.releaseReclaim).toHaveBeenCalledWith(
      { id: 'failed', object_key: 'submissions/u/fail.jpg', reason: 'rejected_upload', reclaim_token: 'lease' },
    );
  });
});
