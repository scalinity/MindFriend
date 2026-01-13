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
exports.SendMessageResponseDto = exports.MessageResponseDto = exports.ConversationResponseDto = exports.SendMessageDto = exports.CreateConversationDto = void 0;
const class_validator_1 = require("class-validator");
class CreateConversationDto {
    title;
}
exports.CreateConversationDto = CreateConversationDto;
__decorate([
    (0, class_validator_1.IsString)(),
    (0, class_validator_1.IsNotEmpty)(),
    (0, class_validator_1.MaxLength)(64),
    __metadata("design:type", String)
], CreateConversationDto.prototype, "title", void 0);
class SendMessageDto {
    content;
}
exports.SendMessageDto = SendMessageDto;
__decorate([
    (0, class_validator_1.IsString)(),
    (0, class_validator_1.IsNotEmpty)(),
    (0, class_validator_1.MaxLength)(2000),
    __metadata("design:type", String)
], SendMessageDto.prototype, "content", void 0);
class ConversationResponseDto {
    id;
    title;
    status;
    createdAt;
    updatedAt;
    lastMessage;
}
exports.ConversationResponseDto = ConversationResponseDto;
class MessageResponseDto {
    id;
    role;
    content;
    createdAt;
    blocked;
}
exports.MessageResponseDto = MessageResponseDto;
class SendMessageResponseDto {
    userMessage;
    assistantMessage;
    quotaRemaining;
    crisisDetected;
}
exports.SendMessageResponseDto = SendMessageResponseDto;
//# sourceMappingURL=chat.dto.js.map