var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
var __metadata = (this && this.__metadata) || function (k, v) {
    if (typeof Reflect === "object" && typeof Reflect.metadata === "function") return Reflect.metadata(k, v);
};
import { Transform } from 'class-transformer';
import { IsIn, IsString, IsUUID, Matches } from 'class-validator';
export class CreateCollabGroupDto {
    userQuestId;
    mode = 'with';
}
__decorate([
    IsUUID(),
    __metadata("design:type", String)
], CreateCollabGroupDto.prototype, "userQuestId", void 0);
__decorate([
    IsIn(['with', 'versus']),
    __metadata("design:type", String)
], CreateCollabGroupDto.prototype, "mode", void 0);
export class JoinCollabGroupDto {
    code;
}
__decorate([
    Transform(({ value }) => typeof value === 'string' ? value.trim().toUpperCase() : value),
    IsString(),
    Matches(/^[A-F0-9]{6}$/),
    __metadata("design:type", String)
], JoinCollabGroupDto.prototype, "code", void 0);
export class CollabCodeParam extends JoinCollabGroupDto {
}
export class CollabAssignmentParam {
    id;
}
__decorate([
    IsUUID(),
    __metadata("design:type", String)
], CollabAssignmentParam.prototype, "id", void 0);
export class CollabVoteParam {
    groupId;
    submissionId;
}
__decorate([
    IsUUID(),
    __metadata("design:type", String)
], CollabVoteParam.prototype, "groupId", void 0);
__decorate([
    IsUUID(),
    __metadata("design:type", String)
], CollabVoteParam.prototype, "submissionId", void 0);
//# sourceMappingURL=collab.dto.js.map