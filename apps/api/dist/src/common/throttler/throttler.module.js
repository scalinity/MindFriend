"use strict";
var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.ThrottlerModule = void 0;
const common_1 = require("@nestjs/common");
const config_1 = require("@nestjs/config");
const throttler_1 = require("@nestjs/throttler");
let ThrottlerModule = class ThrottlerModule {
};
exports.ThrottlerModule = ThrottlerModule;
exports.ThrottlerModule = ThrottlerModule = __decorate([
    (0, common_1.Module)({
        imports: [
            throttler_1.ThrottlerModule.forRootAsync({
                imports: [config_1.ConfigModule],
                inject: [config_1.ConfigService],
                useFactory: (configService) => ({
                    throttlers: [
                        {
                            name: 'default',
                            ttl: parseInt(configService.get('RATE_LIMIT_TTL', '60000'), 10),
                            limit: parseInt(configService.get('RATE_LIMIT_LIMIT', '100'), 10),
                        },
                        {
                            name: 'auth',
                            ttl: 60000,
                            limit: parseInt(configService.get('RATE_LIMIT_AUTH_LIMIT', '10'), 10),
                        },
                        {
                            name: 'chat',
                            ttl: 60000,
                            limit: parseInt(configService.get('RATE_LIMIT_CHAT_LIMIT', '60'), 10),
                        },
                    ],
                }),
            }),
        ],
        exports: [throttler_1.ThrottlerModule],
    })
], ThrottlerModule);
//# sourceMappingURL=throttler.module.js.map