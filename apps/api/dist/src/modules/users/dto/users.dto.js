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
exports.UserProfileResponseDto = exports.RegisterDeviceDto = exports.UpdateSettingsDto = exports.UpdateProfileDto = void 0;
const class_validator_1 = require("class-validator");
class UpdateProfileDto {
    displayName;
    timezone;
}
exports.UpdateProfileDto = UpdateProfileDto;
__decorate([
    (0, class_validator_1.IsString)(),
    (0, class_validator_1.IsOptional)(),
    (0, class_validator_1.MaxLength)(40),
    __metadata("design:type", String)
], UpdateProfileDto.prototype, "displayName", void 0);
__decorate([
    (0, class_validator_1.IsString)(),
    (0, class_validator_1.IsOptional)(),
    (0, class_validator_1.MaxLength)(64),
    __metadata("design:type", String)
], UpdateProfileDto.prototype, "timezone", void 0);
class UpdateSettingsDto {
    dailyQuestTimeLocal;
    quietHoursStartLocal;
    quietHoursEndLocal;
    remindersEnabled;
    nudgeAfterDaysInactive;
    shareMoodInCircles;
    aiTone;
    privacyMode;
}
exports.UpdateSettingsDto = UpdateSettingsDto;
__decorate([
    (0, class_validator_1.IsString)(),
    (0, class_validator_1.IsOptional)(),
    (0, class_validator_1.Matches)(/^\d{2}:\d{2}:\d{2}$/, {
        message: 'dailyQuestTimeLocal must be in HH:mm:ss format',
    }),
    __metadata("design:type", String)
], UpdateSettingsDto.prototype, "dailyQuestTimeLocal", void 0);
__decorate([
    (0, class_validator_1.IsString)(),
    (0, class_validator_1.IsOptional)(),
    (0, class_validator_1.Matches)(/^\d{2}:\d{2}:\d{2}$/, {
        message: 'quietHoursStartLocal must be in HH:mm:ss format',
    }),
    __metadata("design:type", String)
], UpdateSettingsDto.prototype, "quietHoursStartLocal", void 0);
__decorate([
    (0, class_validator_1.IsString)(),
    (0, class_validator_1.IsOptional)(),
    (0, class_validator_1.Matches)(/^\d{2}:\d{2}:\d{2}$/, {
        message: 'quietHoursEndLocal must be in HH:mm:ss format',
    }),
    __metadata("design:type", String)
], UpdateSettingsDto.prototype, "quietHoursEndLocal", void 0);
__decorate([
    (0, class_validator_1.IsBoolean)(),
    (0, class_validator_1.IsOptional)(),
    __metadata("design:type", Boolean)
], UpdateSettingsDto.prototype, "remindersEnabled", void 0);
__decorate([
    (0, class_validator_1.IsInt)(),
    (0, class_validator_1.IsOptional)(),
    (0, class_validator_1.Min)(1),
    (0, class_validator_1.Max)(7),
    __metadata("design:type", Number)
], UpdateSettingsDto.prototype, "nudgeAfterDaysInactive", void 0);
__decorate([
    (0, class_validator_1.IsBoolean)(),
    (0, class_validator_1.IsOptional)(),
    __metadata("design:type", Boolean)
], UpdateSettingsDto.prototype, "shareMoodInCircles", void 0);
__decorate([
    (0, class_validator_1.IsString)(),
    (0, class_validator_1.IsOptional)(),
    (0, class_validator_1.IsIn)(['friendly', 'professional', 'motivational', 'gentle']),
    __metadata("design:type", String)
], UpdateSettingsDto.prototype, "aiTone", void 0);
__decorate([
    (0, class_validator_1.IsString)(),
    (0, class_validator_1.IsOptional)(),
    (0, class_validator_1.IsIn)(['standard', 'enhanced']),
    __metadata("design:type", String)
], UpdateSettingsDto.prototype, "privacyMode", void 0);
class RegisterDeviceDto {
    apnsToken;
    deviceModel;
    osVersion;
    locale;
    timezone;
}
exports.RegisterDeviceDto = RegisterDeviceDto;
__decorate([
    (0, class_validator_1.IsString)(),
    __metadata("design:type", String)
], RegisterDeviceDto.prototype, "apnsToken", void 0);
__decorate([
    (0, class_validator_1.IsString)(),
    (0, class_validator_1.IsOptional)(),
    __metadata("design:type", String)
], RegisterDeviceDto.prototype, "deviceModel", void 0);
__decorate([
    (0, class_validator_1.IsString)(),
    (0, class_validator_1.IsOptional)(),
    __metadata("design:type", String)
], RegisterDeviceDto.prototype, "osVersion", void 0);
__decorate([
    (0, class_validator_1.IsString)(),
    (0, class_validator_1.IsOptional)(),
    __metadata("design:type", String)
], RegisterDeviceDto.prototype, "locale", void 0);
__decorate([
    (0, class_validator_1.IsString)(),
    (0, class_validator_1.IsOptional)(),
    __metadata("design:type", String)
], RegisterDeviceDto.prototype, "timezone", void 0);
class UserProfileResponseDto {
    id;
    handle;
    displayName;
    email;
    timezone;
    createdAt;
    settings;
    stats;
    entitlements;
    badges;
}
exports.UserProfileResponseDto = UserProfileResponseDto;
//# sourceMappingURL=users.dto.js.map