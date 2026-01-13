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
exports.MoodsController = void 0;
const common_1 = require("@nestjs/common");
const moods_service_1 = require("./moods.service");
const moods_dto_1 = require("./dto/moods.dto");
const decorators_1 = require("../../common/decorators");
let MoodsController = class MoodsController {
    moodsService;
    constructor(moodsService) {
        this.moodsService = moodsService;
    }
    async createMood(userId, dto) {
        return this.moodsService.createOrUpdateMood(userId, dto);
    }
    async getMoodHistory(userId, from, to) {
        return this.moodsService.getMoodHistory(userId, from, to);
    }
};
exports.MoodsController = MoodsController;
__decorate([
    (0, common_1.Post)(),
    __param(0, (0, decorators_1.CurrentUser)('sub')),
    __param(1, (0, common_1.Body)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String, moods_dto_1.CreateMoodDto]),
    __metadata("design:returntype", Promise)
], MoodsController.prototype, "createMood", null);
__decorate([
    (0, common_1.Get)(),
    __param(0, (0, decorators_1.CurrentUser)('sub')),
    __param(1, (0, common_1.Query)('from')),
    __param(2, (0, common_1.Query)('to')),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String, String, String]),
    __metadata("design:returntype", Promise)
], MoodsController.prototype, "getMoodHistory", null);
exports.MoodsController = MoodsController = __decorate([
    (0, common_1.Controller)('v1/moods'),
    __metadata("design:paramtypes", [moods_service_1.MoodsService])
], MoodsController);
//# sourceMappingURL=moods.controller.js.map