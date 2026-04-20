import { Test, TestingModule } from '@nestjs/testing';
import { INestApplication } from '@nestjs/common';
import request from 'supertest';
import { App } from 'supertest/types';
import { AppModule } from '../src/app.module';
import { configureApp } from '../src/bootstrap';
import { PrismaService } from '../src/prisma/prisma.service';

describe('FocusFlow API (e2e)', () => {
  let app: INestApplication<App>;

  beforeEach(async () => {
    const mockPrisma = {
      onModuleInit: () => undefined,
      onModuleDestroy: () => undefined,
      $queryRaw: jest.fn().mockResolvedValue([{ ok: 1 }]),
    };

    const moduleFixture: TestingModule = await Test.createTestingModule({
      imports: [AppModule],
    })
      .overrideProvider(PrismaService)
      .useValue(mockPrisma)
      .compile();

    app = moduleFixture.createNestApplication();
    configureApp(app);
    await app.init();
  });

  it('GET /v1/health — liveness', () => {
    return request(app.getHttpServer())
      .get('/v1/health')
      .expect(200)
      .expect((res) => {
        expect(res.body).toEqual({ status: 'ok' });
        expect(res.headers['x-request-id']).toBeDefined();
      });
  });

  it('GET /v1/ready — readiness (Prisma mocked)', () => {
    return request(app.getHttpServer())
      .get('/v1/ready')
      .expect(200)
      .expect((res) => {
        expect(res.body).toMatchObject({ status: 'ok', database: 'up' });
        expect(res.headers['x-request-id']).toBeDefined();
      });
  });

  it('echoes incoming x-request-id header', () => {
    return request(app.getHttpServer())
      .get('/v1/health')
      .set('x-request-id', 'client-trace-123')
      .expect(200)
      .expect((res) => {
        expect(res.headers['x-request-id']).toBe('client-trace-123');
      });
  });

  afterEach(async () => {
    await app.close();
  });
});
