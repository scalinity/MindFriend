"use strict";
var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
var __metadata = (this && this.__metadata) || function (k, v) {
    if (typeof Reflect === "object" && typeof Reflect.metadata === "function") return Reflect.metadata(k, v);
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.JoinCircleResponseDto = exports.CirclePostDto = exports.CircleDetailDto = exports.CircleMemberDto = exports.CircleListItemDto = exports.CircleResponseDto = exports.CircleCheckInDto = exports.JoinCircleDto = exports.CreateCircleDto = void 0;
const class_validator_1 = require("class-validator");
class CreateCircleDto {
    name;
    description;
    maxMembers;
}
exports.CreateCircleDto = CreateCircleDto;
__decorate([
    (0, class_validator_1.IsString)(),
    (0, class_validator_1.IsNotEmpty)(),
    (0, class_validator_1.MaxLength)(40),
    __metadata("design:type", String)
], CreateCircleDto.prototype, "name", void 0);
__decorate([
    (0, class_validator_1.IsString)(),
    (0, class_validator_1.IsOptional)(),
    (0, class_validator_1.MaxLength)(160),
    __metadata("design:type", String)
], CreateCircleDto.prototype, "description", void 0);
__decorate([
    (0, class_validator_1.IsInt)(),
    (0, class_validator_1.Min)(2),
    (0, class_validator_1.Max)(8),
    (0, class_validator_1.IsOptional)(),
    __metadata("design:type", Number)
], CreateCircleDto.prototype, "maxMembers", void 0);
class JoinCircleDto {
    inviteCode;
}
exports.JoinCircleDto = JoinCircleDto;
__decorate([
    (0, class_validator_1.IsString)(),
    (0, class_validator_1.IsNotEmpty)(),
    (0, class_validator_1.MaxLength)(12),
    (0, class_validator_1.Matches)(/^[A-Z0-9]{12}$/, {
        message: 'Invite code must be 12 uppercase alphanumeric characters',
    }),
    __metadata("design:type", String)
], JoinCircleDto.prototype, "inviteCode", void 0);
class CircleCheckInDto {
    localDate;
    moodEmoji;
    bodyText;
}
exports.CircleCheckInDto = CircleCheckInDto;
__decorate([
    (0, class_validator_1.IsString)(),
    (0, class_validator_1.IsNotEmpty)(),
    (0, class_validator_1.Matches)(/^\d{4}-\d{2}-\d{2}$/, {
        message: 'localDate must be in YYYY-MM-DD format',
    }),
    __metadata("design:type", String)
], CircleCheckInDto.prototype, "localDate", void 0);
__decorate([
    (0, class_validator_1.IsString)(),
    (0, class_validator_1.IsOptional)(),
    (0, class_validator_1.MaxLength)(8),
    __metadata("design:type", String)
], CircleCheckInDto.prototype, "moodEmoji", void 0);
__decorate([
    (0, class_validator_1.IsString)(),
    (0, class_validator_1.IsOptional)(),
    (0, class_validator_1.MaxLength)(280),
    __metadata("design:type", String)
], CircleCheckInDto.prototype, "bodyText", void 0);
class CircleResponseDto {
    id;
    name;
    description;
    isPrivate;
    inviteCode;
    maxMembers;
    memberCount;
    role;
    createdAt;
}
exports.CircleResponseDto = CircleResponseDto;
class CircleListItemDto {
    id;
    name;
    memberCount;
    role;
}
exports.CircleListItemDto = CircleListItemDto;
class CircleMemberDto {
    userId;
    handle;
    displayName;
    role;
    joinedAt;
}
exports.CircleMemberDto = CircleMemberDto;
class CircleDetailDto {
    id;
    name;
    description;
    isPrivate;
    inviteCode;
    maxMembers;
    members;
    createdAt;
}
exports.CircleDetailDto = CircleDetailDto;
class CirclePostDto {
    id;
    kind;
    user;
    moodEmoji;
    bodyText;
    localDate;
    createdAt;
}
exports.CirclePostDto = CirclePostDto;
class JoinCircleResponseDto {
    circleId;
    role;
}
exports.JoinCircleResponseDto = JoinCircleResponseDto;
//# sourceMappingURL=circles.dto.js.map