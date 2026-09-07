var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
var __metadata = (this && this.__metadata) || function (k, v) {
    if (typeof Reflect === "object" && typeof Reflect.metadata === "function") return Reflect.metadata(k, v);
};
import { Injectable } from '@nestjs/common';
import { SocialRepository } from '../infrastructure/social.repository.js';
let SocialService = class SocialService {
    repository;
    constructor(repository) {
        this.repository = repository;
    }
    getVote(userId, postId) { return this.repository.getVote(userId, postId); }
    vote(userId, postId, type) { return this.repository.vote(userId, postId, type); }
    removeVote(userId, postId) { return this.repository.removeVote(userId, postId); }
    comments(postId, limit, offset) { return this.repository.listComments(postId, limit, offset); }
    addComment(userId, postId, body, parentId) { return this.repository.addComment(userId, postId, body, parentId); }
    deleteComment(userId, role, id) { return this.repository.deleteComment(userId, role, id); }
    isFollowing(userId, targetId) { return this.repository.isFollowing(userId, targetId); }
    follow(userId, targetId) { return this.repository.follow(userId, targetId); }
    unfollow(userId, targetId) { return this.repository.unfollow(userId, targetId); }
    connections(userId, followers, limit, offset) { return this.repository.connections(userId, followers, limit, offset); }
    counts(userId) { return this.repository.followCounts(userId); }
    block(userId, targetId, reason) { return this.repository.block(userId, targetId, reason); }
    unblock(userId, targetId) { return this.repository.unblock(userId, targetId); }
    blockedUsers(userId, limit, offset) { return this.repository.blockedUsers(userId, limit, offset); }
    report(userId, type, id, reason) { return this.repository.report(userId, type, id, reason); }
    savePost(userId, id, saved) { return this.repository.setSavedPost(userId, id, saved); }
    isPostSaved(userId, id) { return this.repository.isPostSaved(userId, id); }
    saveQuest(userId, id, saved) { return this.repository.setSavedQuest(userId, id, saved); }
    isQuestSaved(userId, id) { return this.repository.isQuestSaved(userId, id); }
    savedQuests(userId, limit, offset) { return this.repository.savedQuests(userId, limit, offset); }
    savedPosts(userId, limit, offset) { return this.repository.savedPosts(userId, limit, offset); }
};
SocialService = __decorate([
    Injectable(),
    __metadata("design:paramtypes", [SocialRepository])
], SocialService);
export { SocialService };
//# sourceMappingURL=social.service.js.map