import { Test, TestingModule } from '@nestjs/testing';
import { INestApplication, ValidationPipe } from '@nestjs/common';
import request from 'supertest';
import { App } from 'supertest/types';
import { AppModule } from './../src/app.module';

describe('App E2E Tests', () => {
  let app: INestApplication<App>;

  beforeAll(async () => {
    const moduleFixture: TestingModule = await Test.createTestingModule({
      imports: [AppModule],
    }).compile();

    app = moduleFixture.createNestApplication();
    app.useGlobalPipes(
      new ValidationPipe({
        whitelist: true,
        transform: true,
      }),
    );
    await app.init();
  });

  afterAll(async () => {
    await app.close();
  });

  describe('Public Endpoints', () => {
    it('/ (GET) should return Hello World', () => {
      return request(app.getHttpServer())
        .get('/')
        .expect(200)
        .expect('Hello World!');
    });

    it('/health (GET) should return health status', () => {
      return request(app.getHttpServer())
        .get('/health')
        .expect(200)
        .expect((res) => {
          expect(res.body).toHaveProperty('status', 'ok');
          expect(res.body).toHaveProperty('timestamp');
          expect(res.body).toHaveProperty('version');
        });
    });
  });

  describe('Protected Endpoints', () => {
    it('/v1/me (GET) should return 401 without auth', () => {
      return request(app.getHttpServer()).get('/v1/me').expect(401);
    });

    it('/v1/quests/today (GET) should return 401 without auth', () => {
      return request(app.getHttpServer()).get('/v1/quests/today').expect(401);
    });

    it('/v1/moods (POST) should return 401 without auth', () => {
      return request(app.getHttpServer())
        .post('/v1/moods')
        .send({ moodScore: 4 })
        .expect(401);
    });

    it('/v1/chat/conversations (POST) should return 401 without auth', () => {
      return request(app.getHttpServer())
        .post('/v1/chat/conversations')
        .send({})
        .expect(401);
    });

    it('/v1/circles (GET) should return 401 without auth', () => {
      return request(app.getHttpServer()).get('/v1/circles').expect(401);
    });
  });

  describe('Auth Endpoints', () => {
    it('/v1/auth/apple (POST) should be public but require valid body', () => {
      return request(app.getHttpServer())
        .post('/v1/auth/apple')
        .send({}) // Missing required fields
        .expect(400);
    });

    it('/v1/auth/refresh (POST) should be public but require valid body', () => {
      return request(app.getHttpServer())
        .post('/v1/auth/refresh')
        .send({}) // Missing required fields
        .expect(400);
    });
  });

  describe('Request ID Middleware', () => {
    it('should add X-Request-Id header to responses', () => {
      return request(app.getHttpServer())
        .get('/')
        .expect(200)
        .expect((res) => {
          expect(res.headers).toHaveProperty('x-request-id');
          // Should be a valid UUID format
          expect(res.headers['x-request-id']).toMatch(
            /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i,
          );
        });
    });

    it('should propagate X-Request-Id from request to response', () => {
      const customRequestId = '12345678-1234-1234-1234-123456789abc';
      return request(app.getHttpServer())
        .get('/')
        .set('X-Request-Id', customRequestId)
        .expect(200)
        .expect((res) => {
          expect(res.headers['x-request-id']).toBe(customRequestId);
        });
    });
  });

  describe('Resources Endpoints', () => {
    it('/v1/resources/crisis (GET) should be public', () => {
      return request(app.getHttpServer())
        .get('/v1/resources/crisis')
        .expect(200)
        .expect((res) => {
          expect(Array.isArray(res.body)).toBe(true);
        });
    });
  });
});
