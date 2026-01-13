"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
var __metadata = (this && this.__metadata) || function (k, v) {
    if (typeof Reflect === "object" && typeof Reflect.metadata === "function") return Reflect.metadata(k, v);
};
var ApnsService_1;
Object.defineProperty(exports, "__esModule", { value: true });
exports.ApnsService = void 0;
const common_1 = require("@nestjs/common");
const config_1 = require("@nestjs/config");
const jwt = __importStar(require("jsonwebtoken"));
const http2 = __importStar(require("http2"));
let ApnsService = ApnsService_1 = class ApnsService {
    configService;
    logger = new common_1.Logger(ApnsService_1.name);
    isMockApns;
    teamId;
    keyId;
    bundleId;
    privateKey;
    apnsHost;
    cachedToken = null;
    constructor(configService) {
        this.configService = configService;
        this.isMockApns = this.configService.get('APNS_MOCK') === 'true';
        this.teamId = this.configService.get('APNS_TEAM_ID', '');
        this.keyId = this.configService.get('APNS_KEY_ID', '');
        this.bundleId = this.configService.get('APNS_BUNDLE_ID', '');
        const privateKeyBase64 = this.configService.get('APNS_PRIVATE_KEY_P8_BASE64', '');
        this.privateKey = privateKeyBase64
            ? Buffer.from(privateKeyBase64, 'base64').toString('utf-8')
            : null;
        const isProduction = this.configService.get('NODE_ENV') === 'production';
        this.apnsHost = isProduction
            ? 'api.push.apple.com'
            : 'api.sandbox.push.apple.com';
    }
    async sendNotification(deviceToken, payload) {
        if (this.isMockApns) {
            return this.mockSendNotification(deviceToken, payload);
        }
        return this.realSendNotification(deviceToken, payload);
    }
    mockSendNotification(deviceToken, payload) {
        this.logger.debug(`[MOCK APNs] Sending to ${deviceToken.substring(0, 8)}...`);
        this.logger.debug(`[MOCK APNs] Payload: ${JSON.stringify(payload)}`);
        return { success: true, statusCode: 200 };
    }
    async realSendNotification(deviceToken, payload) {
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
                const statusCode = headers[':status'];
                req.on('data', (chunk) => {
                    responseData += chunk;
                });
                req.on('end', () => {
                    client.close();
                    if (statusCode === 200) {
                        resolve({ success: true, statusCode });
                    }
                    else {
                        let reason = 'Unknown error';
                        try {
                            const parsed = JSON.parse(responseData);
                            reason = parsed.reason || reason;
                        }
                        catch { }
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
    getProviderToken() {
        const now = Math.floor(Date.now() / 1000);
        if (this.cachedToken && this.cachedToken.expiresAt > now + 60) {
            return this.cachedToken.token;
        }
        const token = jwt.sign({
            iss: this.teamId,
            iat: now,
        }, this.privateKey, {
            algorithm: 'ES256',
            keyid: this.keyId,
        });
        this.cachedToken = {
            token,
            expiresAt: now + 50 * 60,
        };
        return token;
    }
    buildQuestReminderPayload(questId) {
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
    buildInactivityNudgePayload() {
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
};
exports.ApnsService = ApnsService;
exports.ApnsService = ApnsService = ApnsService_1 = __decorate([
    (0, common_1.Injectable)(),
    __metadata("design:paramtypes", [config_1.ConfigService])
], ApnsService);
//# sourceMappingURL=apns.service.js.map