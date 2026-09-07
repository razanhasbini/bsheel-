import { Injectable } from '@nestjs/common';
import { SocialRepository } from '../infrastructure/social.repository.js';

@Injectable()
export class SocialService {
  constructor(private readonly repository: SocialRepository) {}
  getVote(userId: string, postId: string) { return this.repository.getVote(userId, postId); }
  vote(userId: string, postId: string, type: 'upvote' | 'downvote') { return this.repository.vote(userId, postId, type); }
  removeVote(userId: string, postId: string) { return this.repository.removeVote(userId, postId); }
  comments(postId: string, limit: number, offset: number) { return this.repository.listComments(postId, limit, offset); }
  addComment(userId: string, postId: string, body: string, parentId?: string) { return this.repository.addComment(userId, postId, body, parentId); }
  deleteComment(userId: string, role: string, id: string) { return this.repository.deleteComment(userId, role, id); }
  isFollowing(userId: string, targetId: string) { return this.repository.isFollowing(userId, targetId); }
  follow(userId: string, targetId: string) { return this.repository.follow(userId, targetId); }
  unfollow(userId: string, targetId: string) { return this.repository.unfollow(userId, targetId); }
  connections(userId: string, followers: boolean, limit: number, offset: number) { return this.repository.connections(userId, followers, limit, offset); }
  counts(userId: string) { return this.repository.followCounts(userId); }
  block(userId: string, targetId: string, reason: string) { return this.repository.block(userId, targetId, reason); }
  unblock(userId: string, targetId: string) { return this.repository.unblock(userId, targetId); }
  blockedUsers(userId: string, limit: number, offset: number) { return this.repository.blockedUsers(userId, limit, offset); }
  report(userId: string, type: string, id: string, reason: string) { return this.repository.report(userId, type, id, reason); }
  savePost(userId: string, id: string, saved: boolean) { return this.repository.setSavedPost(userId, id, saved); }
  isPostSaved(userId: string, id: string) { return this.repository.isPostSaved(userId, id); }
  saveQuest(userId: string, id: string, saved: boolean) { return this.repository.setSavedQuest(userId, id, saved); }
  isQuestSaved(userId: string, id: string) { return this.repository.isQuestSaved(userId, id); }
  savedQuests(userId: string, limit: number, offset: number) { return this.repository.savedQuests(userId, limit, offset); }
  savedPosts(userId: string, limit: number, offset: number) { return this.repository.savedPosts(userId, limit, offset); }
}
