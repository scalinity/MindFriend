import { Module } from '@nestjs/common';
import { ConfigModule, ConfigService } from '@nestjs/config';
import { ThrottlerModule as NestThrottlerModule } from '@nestjs/throttler';

@Module({
  imports: [
    NestThrottlerModule.forRootAsync({
      imports: [ConfigModule],
      inject: [ConfigService],
      useFactory: (configService: ConfigService) => ({
        throttlers: [
          {
            name: 'default',
            ttl: parseInt(configService.get('RATE_LIMIT_TTL', '60000'), 10),
            limit: parseInt(configService.get('RATE_LIMIT_LIMIT', '100'), 10),
          },
          {
            name: 'auth',
            ttl: 60000, // 1 minute
            limit: parseInt(
              configService.get('RATE_LIMIT_AUTH_LIMIT', '10'),
              10,
            ),
          },
          {
            name: 'chat',
            ttl: 60000, // 1 minute
            limit: parseInt(
              configService.get('RATE_LIMIT_CHAT_LIMIT', '60'),
              10,
            ),
          },
        ],
      }),
    }),
  ],
  exports: [NestThrottlerModule],
})
export class ThrottlerModule {}
