import { NotificationType } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { ApnsService } from './apns.service';
import { NotificationResponseDto } from './dto/notifications.dto';
interface SendNotificationParams {
    userId: string;
    type: NotificationType;
    title: string;
    body: string;
    data?: Record<string, any>;
}
export declare class NotificationsService {
    private readonly prisma;
    private readonly apnsService;
    private readonly logger;
    constructor(prisma: PrismaService, apnsService: ApnsService);
    sendNotification(params: SendNotificationParams): Promise<NotificationResponseDto>;
    sendQuestReminder(userId: string, questId: string): Promise<void>;
    sendInactivityNudge(userId: string): Promise<void>;
    private isInQuietHours;
    private formatNotification;
}
export {};
