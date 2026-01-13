import { Injectable, Logger } from '@nestjs/common';
import { NotificationType, NotificationStatus } from '@prisma/client';
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

@Injectable()
export class NotificationsService {
  private readonly logger = new Logger(NotificationsService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly apnsService: ApnsService,
  ) {}

  async sendNotification(
    params: SendNotificationParams,
  ): Promise<NotificationResponseDto> {
    // Get user's active device
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
      // Create notification record marked as failed (no device)
      const notification = await this.prisma.notification.create({
        data: {
          userId: params.userId,
          deviceId: null,
          type: params.type,
          title: params.title,
          body: params.body,
          dataJson: params.data || {},
          scheduledAt: new Date(),
          status: NotificationStatus.failed,
        },
      });

      return this.formatNotification(notification);
    }

    // Check quiet hours
    const userSettings = await this.prisma.userSettings.findUnique({
      where: { userId: params.userId },
    });

    if (userSettings && this.isInQuietHours(userSettings)) {
      this.logger.debug(
        `User ${params.userId} is in quiet hours, skipping notification`,
      );
      const notification = await this.prisma.notification.create({
        data: {
          userId: params.userId,
          deviceId: device.id,
          type: params.type,
          title: params.title,
          body: params.body,
          dataJson: params.data || {},
          scheduledAt: new Date(),
          status: NotificationStatus.canceled,
        },
      });

      return this.formatNotification(notification);
    }

    // Build APNs payload
    const payload = {
      aps: {
        alert: {
          title: params.title,
          body: params.body,
        },
        sound: 'default' as const,
        badge: 1,
      },
      type: params.type,
      ...(params.data || {}),
    };

    // Send notification
    const result = await this.apnsService.sendNotification(
      device.apnsToken,
      payload,
    );

    // Handle device token errors
    if (
      !result.success &&
      (result.reason === 'BadDeviceToken' || result.reason === 'Unregistered')
    ) {
      await this.prisma.device.update({
        where: { id: device.id },
        data: { pushEnabled: false },
      });
      this.logger.warn(
        `Disabled push for device ${device.id} due to: ${result.reason}`,
      );
    }

    // Create notification record
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
          ? NotificationStatus.sent
          : NotificationStatus.failed,
      },
    });

    return this.formatNotification(notification);
  }

  async sendQuestReminder(userId: string, questId: string): Promise<void> {
    await this.sendNotification({
      userId,
      type: NotificationType.daily_quest,
      title: 'Daily Quest',
      body: 'Your wellness quest is ready! Take a moment for yourself.',
      data: { questId },
    });
  }

  async sendInactivityNudge(userId: string): Promise<void> {
    await this.sendNotification({
      userId,
      type: NotificationType.inactivity_nudge,
      title: 'We miss you!',
      body: "It's been a while. Ready to check in?",
    });
  }

  private isInQuietHours(settings: any): boolean {
    if (!settings.quietHoursStartLocal || !settings.quietHoursEndLocal) {
      return false;
    }

    const now = new Date();

    // Get user's local time
    const formatter = new Intl.DateTimeFormat('en-US', {
      timeZone: settings.timezone || 'UTC',
      hour: '2-digit',
      minute: '2-digit',
      hour12: false,
    });

    const localTime = formatter.format(now);
    const [hours, minutes] = localTime.split(':').map(Number);
    const currentMinutes = hours * 60 + minutes;

    // Parse quiet hours
    const [startHours, startMinutes] = settings.quietHoursStartLocal
      .split(':')
      .map(Number);
    const [endHours, endMinutes] = settings.quietHoursEndLocal
      .split(':')
      .map(Number);

    const startMinutesOfDay = startHours * 60 + startMinutes;
    const endMinutesOfDay = endHours * 60 + endMinutes;

    // Handle overnight quiet hours (e.g., 22:00 - 08:00)
    if (startMinutesOfDay > endMinutesOfDay) {
      return (
        currentMinutes >= startMinutesOfDay || currentMinutes < endMinutesOfDay
      );
    }

    return (
      currentMinutes >= startMinutesOfDay && currentMinutes < endMinutesOfDay
    );
  }

  private formatNotification(notification: any): NotificationResponseDto {
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
}
