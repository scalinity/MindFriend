import { ConfigService } from '@nestjs/config';
interface APNsPayload {
    aps: {
        alert: {
            title: string;
            body: string;
        };
        sound?: string;
        badge?: number;
    };
    [key: string]: any;
}
interface APNsResponse {
    success: boolean;
    statusCode?: number;
    reason?: string;
}
export declare class ApnsService {
    private readonly configService;
    private readonly logger;
    private readonly isMockApns;
    private readonly teamId;
    private readonly keyId;
    private readonly bundleId;
    private readonly privateKey;
    private readonly apnsHost;
    private cachedToken;
    constructor(configService: ConfigService);
    sendNotification(deviceToken: string, payload: APNsPayload): Promise<APNsResponse>;
    private mockSendNotification;
    private realSendNotification;
    private getProviderToken;
    buildQuestReminderPayload(questId: string): APNsPayload;
    buildInactivityNudgePayload(): APNsPayload;
}
export {};
