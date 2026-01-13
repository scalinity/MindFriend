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
exports.QuestCompletionResponseDto = exports.QuestResponseDto = exports.CompleteQuestDto = void 0;
const class_validator_1 = require("class-validator");
class CompleteQuestDto {
    reflectionNote;
    rating;
}
exports.CompleteQuestDto = CompleteQuestDto;
__decorate([
    (0, class_validator_1.IsString)(),
    (0, class_validator_1.IsOptional)(),
    __metadata("design:type", String)
], CompleteQuestDto.prototype, "reflectionNote", void 0);
__decorate([
    (0, class_validator_1.IsInt)(),
    (0, class_validator_1.IsOptional)(),
    (0, class_validator_1.Min)(1),
    (0, class_validator_1.Max)(5),
    __metadata("design:type", Number)
], CompleteQuestDto.prototype, "rating", void 0);
class QuestResponseDto {
    id;
    localDate;
    status;
    assignedAt;
    completedAt;
    template;
}
exports.QuestResponseDto = QuestResponseDto;
class QuestCompletionResponseDto {
    questId;
    status;
    completedAt;
    streakDays;
    badgesEarned;
}
exports.QuestCompletionResponseDto = QuestCompletionResponseDto;
//# sourceMappingURL=quests.dto.js.map