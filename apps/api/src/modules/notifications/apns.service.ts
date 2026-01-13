import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import * as jwt from 'jsonwebtoken';
import * as http2 from 'http2';

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

@Injectable()
export class ApnsService {
  private readonly logger = new Logger(ApnsService.name);
  private readonly isMockApns: boolean;
  private readonly teamId: string;
  private readonly keyId: string;
  private readonly bundleId: string;
  private readonly privateKey: string | null;
  private readonly apnsHost: string;
  private cachedToken: { token: string; expiresAt: number } | null = null;

  constructor(private readonly configService: ConfigService) {
    this.isMockApns = this.configService.get('APNS_MOCK') === 'true';
    this.teamId = this.configService.get('APNS_TEAM_ID', '');
    this.keyId = this.configService.get('APNS_KEY_ID', '');
    this.bundleId = this.configService.get('APNS_BUNDLE_ID', '');

    // Private key is base64 encoded in env
    const privateKeyBase64 = this.configService.get(
      'APNS_PRIVATE_KEY_P8_BASE64',
      '',
    );
    this.privateKey = privateKeyBase64
      ? Buffer.from(privateKeyBase64, 'base64').toString('utf-8')
      : null;

    // Use sandbox in development, production in prod
    const isProduction = this.configService.get('NODE_ENV') === 'production';
    this.apnsHost = isProduction
      ? 'api.push.apple.com'
      : 'api.sandbox.push.apple.com';
  }

  async sendNotification(
    deviceToken: string,
    payload: APNsPayload,
  ): Promise<APNsResponse> {
    if (this.isMockApns) {
      return this.mockSendNotification(deviceToken, payload);
    }

    return this.realSendNotification(deviceToken, payload);
  }

  private mockSendNotification(
    deviceToken: string,
    payload: APNsPayload,
  ): APNsResponse {
    this.logger.debug(
      `[MOCK APNs] Sending to ${deviceToken.substring(0, 8)}...`,
    );
    this.logger.debug(`[MOCK APNs] Payload: ${JSON.stringify(payload)}`);
    return { success: true, statusCode: 200 };
  }

  private async realSendNotification(
    deviceToken: string,
    payload: APNsPayload,
  ): Promise<APNsResponse> {
    if (!this.privateKey) {
      this.logger.error('APNs private key not configured');
      return { success: false, reason: 'APNs not configured' };
    }

    const token = this.getProviderToken();

    return new Promise((resolve) => {
      const client = http2.connect(`https://${this.apnsHost}`);

      client.on('error', (err) => {
        this.logger.error('APNs connection error', err);
        client.close();
        resolve({ success: false, reason: 'Connection error' });
      });

      const headers = {
        ':method': 'POST',
        ':path': `/3/device/${deviceToken}`,
        authorization: `bearer ${token}`,
        'apns-topic': this.bundleId,
        'apns-push-type': 'alert',
        'apns-priority': '10',
      };

      const req = client.request(headers);
      let responseData = '';

      req.on('response', (headers) => {
        const statusCode = headers[':status'] as number;

        req.on('data', (chunk) => {
          responseData += chunk;
        });

        req.on('end', () => {
          client.close();

          if (statusCode === 200) {
            resolve({ success: true, statusCode });
          } else {
            let reason = 'Unknown error';
            try {
              const parsed = JSON.parse(responseData);
              reason = parsed.reason || reason;
            } catch {}
            this.logger.warn(`APNs error: ${statusCode} - ${reason}`);
            resolve({ success: false, statusCode, reason });
          }
        });
      });

      req.on('error', (err) => {
        this.logger.error('APNs request error', err);
        client.close();
        resolve({ success: false, reason: 'Request error' });
      });

      req.write(JSON.stringify(payload));
      req.end();
    });
  }

  private getProviderToken(): string {
    const now = Math.floor(Date.now() / 1000);

    // Return cached token if still valid (tokens are valid for 1 hour)
    if (this.cachedToken && this.cachedToken.expiresAt > now + 60) {
      return this.cachedToken.token;
    }

    // Generate new token
    const token = jwt.sign(
      {
        iss: this.teamId,
        iat: now,
      },
      this.privateKey!,
      {
        algorithm: 'ES256',
        keyid: this.keyId,
      },
    );

    // Cache for 50 minutes (tokens valid for 1 hour)
    this.cachedToken = {
      token,
      expiresAt: now + 50 * 60,
    };

    return token;
  }

  buildQuestReminderPayload(questId: string): APNsPayload {
    return {
      aps: {
        alert: {
          title: 'Daily Quest',
          body: 'Your wellness quest is ready! Take a moment for yourself.',
        },
        sound: 'default',
        badge: 1,
      },
      type: 'daily_quest',
      questId,
    };
  }

  buildInactivityNudgePayload(): APNsPayload {
    return {
      aps: {
        alert: {
          title: 'We miss you!',
          body: "It's been a while. Ready to check in?",
        },
        sound: 'default',
      },
      type: 'inactivity_nudge',
    };
  }
}
