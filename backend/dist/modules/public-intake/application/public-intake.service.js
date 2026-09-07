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
import { PublicIntakeRepository } from '../infrastructure/public-intake.repository.js';
let PublicIntakeService = class PublicIntakeService {
    repository;
    constructor(repository) {
        this.repository = repository;
    }
    joinWaitlist(email, source) { return this.repository.joinWaitlist(email, source); }
    submitSuggestion(input) { return this.repository.submitSuggestion(input); }
};
PublicIntakeService = __decorate([
    Injectable(),
    __metadata("design:paramtypes", [PublicIntakeRepository])
], PublicIntakeService);
export { PublicIntakeService };
//# sourceMappingURL=public-intake.service.js.map