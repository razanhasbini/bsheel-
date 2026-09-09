import { Injectable, NotFoundException } from '@nestjs/common';
import {
  QuestCampaignsRepository,
  type ChainRecord,
  type CollectionRecord,
} from '../infrastructure/quest-campaigns.repository.js';

/// Chains and collections for the admin console (#56).
///
/// Thin by design: the interesting behaviour is ordering and uniqueness,
/// which belongs next to the transactions that enforce it. This layer exists
/// to turn a missing row into a 404 rather than a null the controller has to
/// interpret.
@Injectable()
export class QuestCampaignsService {
  constructor(private readonly repository: QuestCampaignsRepository) {}

  listChains(): Promise<readonly ChainRecord[]> { return this.repository.listChains(); }

  async chainDetail(id: string): Promise<Record<string, unknown>> {
    const chain = await this.repository.chainDetail(id);
    if (!chain) throw new NotFoundException({ code: 'CHAIN_NOT_FOUND', message: 'Chain not found' });
    return chain;
  }

  createChain(input: { name: string; description: string; mode: 'solo' | 'group'; isActive: boolean }, actorId: string) {
    return this.repository.createChain(input, actorId);
  }

  async updateChain(id: string, input: { name?: string; description?: string; mode?: 'solo' | 'group'; isActive?: boolean }) {
    const chain = await this.repository.updateChain(id, input);
    if (!chain) throw new NotFoundException({ code: 'CHAIN_NOT_FOUND', message: 'Chain not found' });
    return chain;
  }

  deleteChain(id: string) { return this.repository.deleteChain(id); }
  appendStep(chainId: string, questId: string, actorId: string) { return this.repository.appendStep(chainId, questId, actorId); }
  removeStep(chainId: string, questId: string, actorId: string) { return this.repository.removeStep(chainId, questId, actorId); }
  reorderStep(chainId: string, questId: string, toOrder: number, actorId: string) {
    return this.repository.reorderStep(chainId, questId, toOrder, actorId);
  }

  listCollections(): Promise<readonly CollectionRecord[]> { return this.repository.listCollections(); }

  async collectionDetail(id: string): Promise<Record<string, unknown>> {
    const collection = await this.repository.collectionDetail(id);
    if (!collection) throw new NotFoundException({ code: 'COLLECTION_NOT_FOUND', message: 'Collection not found' });
    return collection;
  }

  createCollection(
    input: { name: string; description: string; countryCode: string | null; isPublished: boolean },
    actorId: string,
  ) {
    return this.repository.createCollection(input, actorId);
  }

  async updateCollection(
    id: string,
    input: { name?: string; description?: string; countryCode?: string | null; isPublished?: boolean },
  ) {
    const collection = await this.repository.updateCollection(id, input);
    if (!collection) throw new NotFoundException({ code: 'COLLECTION_NOT_FOUND', message: 'Collection not found' });
    return collection;
  }

  deleteCollection(id: string) { return this.repository.deleteCollection(id); }
  addToCollection(collectionId: string, questId: string, actorId: string) {
    return this.repository.addToCollection(collectionId, questId, actorId);
  }
  removeFromCollection(collectionId: string, questId: string, actorId: string) {
    return this.repository.removeFromCollection(collectionId, questId, actorId);
  }

  assignableQuests(scope: 'chain' | 'collection', search: string) {
    return this.repository.assignableQuests(scope, search);
  }
}
