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
exports.CirclesController = void 0;
const common_1 = require("@nestjs/common");
const circles_service_1 = require("./circles.service");
const circles_dto_1 = require("./dto/circles.dto");
const decorators_1 = require("../../common/decorators");
let CirclesController = class CirclesController {
    circlesService;
    constructor(circlesService) {
        this.circlesService = circlesService;
    }
    async createCircle(userId, dto) {
        return this.circlesService.createCircle(userId, dto);
    }
    async joinCircle(userId, dto) {
        return this.circlesService.joinCircle(userId, dto);
    }
    async getCircles(userId) {
        return this.circlesService.getCircles(userId);
    }
    async getCircleDetail(userId, circleId) {
        return this.circlesService.getCircleDetail(userId, circleId);
    }
    async getCircleFeed(userId, circleId, from, to) {
        return this.circlesService.getCircleFeed(userId, circleId, from, to);
    }
    async postCheckIn(userId, circleId, dto) {
        return this.circlesService.postCheckIn(userId, circleId, dto);
    }
};
exports.CirclesController = CirclesController;
__decorate([
    (0, common_1.Post)(),
    __param(0, (0, decorators_1.CurrentUser)('sub')),
    __param(1, (0, common_1.Body)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String, circles_dto_1.CreateCircleDto]),
    __metadata("design:returntype", Promise)
], CirclesController.prototype, "createCircle", null);
__decorate([
    (0, common_1.Post)('join'),
    __param(0, (0, decorators_1.CurrentUser)('sub')),
    __param(1, (0, common_1.Body)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String, circles_dto_1.JoinCircleDto]),
    __metadata("design:returntype", Promise)
], CirclesController.prototype, "joinCircle", null);
__decorate([
    (0, common_1.Get)(),
    __param(0, (0, decorators_1.CurrentUser)('sub')),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String]),
    __metadata("design:returntype", Promise)
], CirclesController.prototype, "getCircles", null);
__decorate([
    (0, common_1.Get)(':id'),
    __param(0, (0, decorators_1.CurrentUser)('sub')),
    __param(1, (0, common_1.Param)('id')),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String, String]),
    __metadata("design:returntype", Promise)
], CirclesController.prototype, "getCircleDetail", null);
__decorate([
    (0, common_1.Get)(':id/feed'),
    __param(0, (0, decorators_1.CurrentUser)('sub')),
    __param(1, (0, common_1.Param)('id')),
    __param(2, (0, common_1.Query)('from')),
    __param(3, (0, common_1.Query)('to')),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String, String, String, String]),
    __metadata("design:returntype", Promise)
], CirclesController.prototype, "getCircleFeed", null);
__decorate([
    (0, common_1.Post)(':id/checkin'),
    __param(0, (0, decorators_1.CurrentUser)('sub')),
    __param(1, (0, common_1.Param)('id')),
    __param(2, (0, common_1.Body)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String, String, circles_dto_1.CircleCheckInDto]),
    __metadata("design:returntype", Promise)
], CirclesController.prototype, "postCheckIn", null);
exports.CirclesController = CirclesController = __decorate([
    (0, common_1.Controller)('v1/circles'),
    __metadata("design:paramtypes", [circles_service_1.CirclesService])
], CirclesController);
//# sourceMappingURL=circles.controller.js.map