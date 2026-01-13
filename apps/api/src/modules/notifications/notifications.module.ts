import { Module } from '@nestjs/common';
import { NotificationsService } from './notifications.service';
import { ApnsService } from './apns.service';

@Module({
  providers: [NotificationsService, ApnsService],
  exports: [NotificationsService, ApnsService],
})
export class NotificationsModule {}
