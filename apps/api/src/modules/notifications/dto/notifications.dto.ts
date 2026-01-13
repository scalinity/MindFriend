export class NotificationResponseDto {
  id: string;
  type: string;
  title: string;
  body: string;
  status: string;
  scheduledAt: Date;
  sentAt: Date | null;
}
