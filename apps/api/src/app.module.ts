import { Module, MiddlewareConsumer, NestModule } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { APP_FILTER, APP_GUARD } from '@nestjs/core';
import { JwtModule } from '@nestjs/jwt';
import { ThrottlerGuard } from '@nestjs/throttler';
import { RequestIdMiddleware } from './common/middleware';
import { PrismaModule } from './modules/prisma/prisma.module';
import { ThrottlerModule } from './common/throttler';
import { AuthModule } from './modules/auth/auth.module';
import { UsersModule } from './modules/users/users.module';
import { QuestsModule } from './modules/quests/quests.module';
import { MoodsModule } from './modules/moods/moods.module';
import { ChatModule } from './modules/chat/chat.module';
import { CirclesModule } from './modules/circles/circles.module';
import { ExercisesModule } from './modules/exercises/exercises.module';
import { ResourcesModule } from './modules/resources/resources.module';
import { BillingModule } from './modules/billing/billing.module';
import { NotificationsModule } from './modules/notifications/notifications.module';
import { AllExceptionsFilter } from './common/filters/all-exceptions.filter';
import { JwtAuthGuard } from './common/guards/jwt-auth.guard';
import { AppController } from './app.controller';
import { AppService } from './app.service';

@Module({
  imports: [
    // Configuration
    ConfigModule.forRoot({
      isGlobal: true,
      envFilePath: '.env',
    }),

    // JWT for global guard
    JwtModule.register({
      global: true,
    }),

    // Database
    PrismaModule,

    // Rate Limiting
    ThrottlerModule,

    // Feature Modules
    AuthModule,
    UsersModule,
    QuestsModule,
    MoodsModule,
    ChatModule,
    CirclesModule,
    ExercisesModule,
    ResourcesModule,
    BillingModule,
    NotificationsModule,
  ],
  controllers: [AppController],
  providers: [
    AppService,

    // Global exception filter
    {
      provide: APP_FILTER,
      useClass: AllExceptionsFilter,
    },

    // Global JWT auth guard
    {
      provide: APP_GUARD,
      useClass: JwtAuthGuard,
    },

    // Global rate limiting guard
    {
      provide: APP_GUARD,
      useClass: ThrottlerGuard,
    },
  ],
})
export class AppModule implements NestModule {
  configure(consumer: MiddlewareConsumer) {
    // Apply request ID middleware to all routes
    consumer.apply(RequestIdMiddleware).forRoutes('*');
  }
}
