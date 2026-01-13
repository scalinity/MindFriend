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
exports.MoodHistoryResponseDto = exports.MoodEntryResponseDto = exports.CreateMoodDto = void 0;
const class_validator_1 = require("class-validator");
class CreateMoodDto {
    moodScore;
    anxietyScore;
    energyScore;
    note;
    source;
}
exports.CreateMoodDto = CreateMoodDto;
__decorate([
    (0, class_validator_1.IsInt)(),
    (0, class_validator_1.Min)(1),
    (0, class_validator_1.Max)(5),
    __metadata("design:type", Number)
], CreateMoodDto.prototype, "moodScore", void 0);
__decorate([
    (0, class_validator_1.IsInt)(),
    (0, class_validator_1.IsOptional)(),
    (0, class_validator_1.Min)(1),
    (0, class_validator_1.Max)(5),
    __metadata("design:type", Number)
], CreateMoodDto.prototype, "anxietyScore", void 0);
__decorate([
    (0, class_validator_1.IsInt)(),
    (0, class_validator_1.IsOptional)(),
    (0, class_validator_1.Min)(1),
    (0, class_validator_1.Max)(5),
    __metadata("design:type", Number)
], CreateMoodDto.prototype, "energyScore", void 0);
__decorate([
    (0, class_validator_1.IsString)(),
    (0, class_validator_1.IsOptional)(),
    __metadata("design:type", String)
], CreateMoodDto.prototype, "note", void 0);
__decorate([
    (0, class_validator_1.IsString)(),
    (0, class_validator_1.IsOptional)(),
    (0, class_validator_1.IsIn)(['manual', 'quest', 'circle_checkin']),
    __metadata("design:type", String)
], CreateMoodDto.prototype, "source", void 0);
class MoodEntryResponseDto {
    id;
    localDate;
    moodScore;
    anxietyScore;
    energyScore;
    note;
    source;
    createdAt;
}
exports.MoodEntryResponseDto = MoodEntryResponseDto;
class MoodHistoryResponseDto {
    entries;
    summary;
}
exports.MoodHistoryResponseDto = MoodHistoryResponseDto;
//# sourceMappingURL=moods.dto.js.map