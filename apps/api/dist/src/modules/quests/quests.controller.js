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
var __param = (this && this.__param) || function (paramIndex, decorator) {
    return function (target, key) { decorator(target, key, paramIndex); }
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.QuestsController = void 0;
const common_1 = require("@nestjs/common");
const quests_service_1 = require("./quests.service");
const quests_dto_1 = require("./dto/quests.dto");
const decorators_1 = require("../../common/decorators");
let QuestsController = class QuestsController {
    questsService;
    constructor(questsService) {
        this.questsService = questsService;
    }
    async getTodayQuest(userId) {
        return this.questsService.getTodayQuest(userId);
    }
    async completeQuest(userId, questId, dto) {
        return this.questsService.completeQuest(userId, questId, dto);
    }
    async skipQuest(userId, questId) {
        return this.questsService.skipQuest(userId, questId);
    }
};
exports.QuestsController = QuestsController;
__decorate([
    (0, common_1.Get)('today'),
    __param(0, (0, decorators_1.CurrentUser)('sub')),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String]),
    __metadata("design:returntype", Promise)
], QuestsController.prototype, "getTodayQuest", null);
__decorate([
    (0, common_1.Post)(':id/complete'),
    __param(0, (0, decorators_1.CurrentUser)('sub')),
    __param(1, (0, common_1.Param)('id')),
    __param(2, (0, common_1.Body)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String, String, quests_dto_1.CompleteQuestDto]),
    __metadata("design:returntype", Promise)
], QuestsController.prototype, "completeQuest", null);
__decorate([
    (0, common_1.Post)(':id/skip'),
    __param(0, (0, decorators_1.CurrentUser)('sub')),
    __param(1, (0, common_1.Param)('id')),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String, String]),
    __metadata("design:returntype", Promise)
], QuestsController.prototype, "skipQuest", null);
exports.QuestsController = QuestsController = __decorate([
    (0, common_1.Controller)('v1/quests'),
    __metadata("design:paramtypes", [quests_service_1.QuestsService])
], QuestsController);
//# sourceMappingURL=quests.controller.js.map