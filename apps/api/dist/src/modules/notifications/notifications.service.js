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
var NotificationsService_1;
Object.defineProperty(exports, "__esModule", { value: true });
exports.NotificationsService = void 0;
const common_1 = require("@nestjs/common");
const client_1 = require("@prisma/client");
const prisma_service_1 = require("../prisma/prisma.service");
const apns_service_1 = require("./apns.service");
let NotificationsService = NotificationsService_1 = class NotificationsService {
    prisma;
    apnsService;
    logger = new common_1.Logger(NotificationsService_1.name);
    constructor(prisma, apnsService) {
        this.prisma = prisma;
        this.apnsService = apnsService;
    }
    async sendNotification(params) {
        const device = await this.prisma.device.findFirst({
            where: {
                userId: params.userId,
                pushEnabled: true,
                apnsToken: { not: null },
            },
            orderBy: { lastSeenAt: 'desc' },
        });
        if (!device || !device.apnsToken) {
            this.logger.warn(`No push-enabled device for user ${params.userId}`);
            const notification = await this.prisma.notification.create({
                data: {
                    userId: params.userId,
                    deviceId: null,
                    type: params.type,
                    title: params.title,
                    body: params.body,
                    dataJson: params.data || {},
                    scheduledAt: new Date(),
                    status: client_1.NotificationStatus.failed,
                },
            });
            return this.formatNotification(notification);
        }
        const userSettings = await this.prisma.userSettings.findUnique({
            where: { userId: params.userId },
        });
        if (userSettings && this.isInQuietHours(userSettings)) {
            this.logger.debug(`User ${params.userId} is in quiet hours, skipping notification`);
            const notification = await this.prisma.notification.create({
                data: {
                    userId: params.userId,
                    deviceId: device.id,
                    type: params.type,
                    title: params.title,
                    body: params.body,
                    dataJson: params.data || {},
                    scheduledAt: new Date(),
                    status: client_1.NotificationStatus.canceled,
                },
            });
            return this.formatNotification(notification);
        }
        const payload = {
            aps: {
                alert: {
                    title: params.title,
                    body: params.body,
                },
                sound: 'default',
                badge: 1,
            },
            type: params.type,
            ...(params.data || {}),
        };
        const result = await this.apnsService.sendNotification(device.apnsToken, payload);
        if (!result.success &&
            (result.reason === 'BadDeviceToken' || result.reason === 'Unregistered')) {
            await this.prisma.device.update({
                where: { id: device.id },
                data: { pushEnabled: false },
            });
            this.logger.warn(`Disabled push for device ${device.id} due to: ${result.reason}`);
        }
        const notification = await this.prisma.notification.create({
            data: {
                userId: params.userId,
                deviceId: device.id,
                type: params.type,
                title: params.title,
                body: params.body,
                dataJson: params.data || {},
                scheduledAt: new Date(),
                sentAt: result.success ? new Date() : null,
                status: result.success
                    ? client_1.NotificationStatus.sent
                    : client_1.NotificationStatus.failed,
            },
        });
        return this.formatNotification(notification);
    }
    async sendQuestReminder(userId, questId) {
        await this.sendNotification({
            userId,
            type: client_1.NotificationType.daily_quest,
            title: 'Daily Quest',
            body: 'Your wellness quest is ready! Take a moment for yourself.',
            data: { questId },
        });
    }
    async sendInactivityNudge(userId) {
        await this.sendNotification({
            userId,
            type: client_1.NotificationType.inactivity_nudge,
            title: 'We miss you!',
            body: "It's been a while. Ready to check in?",
        });
    }
    isInQuietHours(settings) {
        if (!settings.quietHoursStartLocal || !settings.quietHoursEndLocal) {
            return false;
        }
        const now = new Date();
        const formatter = new Intl.DateTimeFormat('en-US', {
            timeZone: settings.timezone || 'UTC',
            hour: '2-digit',
            minute: '2-digit',
            hour12: false,
        });
        const localTime = formatter.format(now);
        const [hours, minutes] = localTime.split(':').map(Number);
        const currentMinutes = hours * 60 + minutes;
        const [startHours, startMinutes] = settings.quietHoursStartLocal
            .split(':')
            .map(Number);
        const [endHours, endMinutes] = settings.quietHoursEndLocal
            .split(':')
            .map(Number);
        const startMinutesOfDay = startHours * 60 + startMinutes;
        const endMinutesOfDay = endHours * 60 + endMinutes;
        if (startMinutesOfDay > endMinutesOfDay) {
            return (currentMinutes >= startMinutesOfDay || currentMinutes < endMinutesOfDay);
        }
        return (currentMinutes >= startMinutesOfDay && currentMinutes < endMinutesOfDay);
    }
    formatNotification(notification) {
        return {
            id: notification.id,
            type: notification.type,
            title: notification.title,
            body: notification.body,
            status: notification.status,
            scheduledAt: notification.scheduledAt,
            sentAt: notification.sentAt,
        };
    }
};
exports.NotificationsService = NotificationsService;
exports.NotificationsService = NotificationsService = NotificationsService_1 = __decorate([
    (0, common_1.Injectable)(),
    __metadata("design:paramtypes", [prisma_service_1.PrismaService,
        apns_service_1.ApnsService])
], NotificationsService);
//# sourceMappingURL=notifications.service.js.map