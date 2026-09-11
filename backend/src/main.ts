import { Logger, ValidationPipe, VersioningType } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { NestFactory } from '@nestjs/core';
import { DocumentBuilder, SwaggerModule } from '@nestjs/swagger';
import compression from 'compression';
import helmet from 'helmet';
import { Logger as PinoLogger } from 'nestjs-pino';
import { AppModule } from './app.module.js';
import type { Environment } from './config/environment.js';
import { ConfiguredSocketIoAdapter } from './infrastructure/realtime/configured-socket-io.adapter.js';

async function bootstrap() {
  const app = await NestFactory.create(AppModule, { bufferLogs: true });
  const config = app.get(ConfigService<Environment, true>);
  app.useLogger(app.get(PinoLogger));
  app.enableShutdownHooks();
  app.use(helmet());
  app.use(compression());
  app.enableCors({
    credentials: true,
    origin: config
      .get('CORS_ORIGINS', { infer: true })
      .split(',')
      .map((origin) => origin.trim()),
  });
  const allowedOrigins = config
    .get('CORS_ORIGINS', { infer: true })
    .split(',')
    .map((origin) => origin.trim());
  app.useWebSocketAdapter(new ConfiguredSocketIoAdapter(app, allowedOrigins));
  app.setGlobalPrefix(config.get('API_PREFIX', { infer: true }), {
    // Three paths must live at the domain root, outside /api/v1.
    //
    // Apple and Google fetch the association files from a fixed location and
    // will not follow a prefix; if they 404 there, the OS never learns the
    // app owns these links and every one of them opens in a browser instead.
    // That is precisely what happened in TestFlight: sign-in completed and
    // then dead-ended in Safari.
    //
    // The callback page is rooted for the same reason — it is the URL those
    // files claim, so the two have to agree.
    exclude: [
      '.well-known/apple-app-site-association',
      '.well-known/assetlinks.json',
      'phone-signin-callback',
    ],
  });
  app.enableVersioning({ type: VersioningType.URI, defaultVersion: '1' });
  app.useGlobalPipes(
    new ValidationPipe({
      transform: true,
      whitelist: true,
      forbidNonWhitelisted: true,
      stopAtFirstError: false,
    }),
  );

  if (config.get('SWAGGER_ENABLED', { infer: true })) {
    const document = SwaggerModule.createDocument(
      app,
      new DocumentBuilder()
        .setTitle('Bsheel API')
        .setDescription('Versioned contract for the Bsheel mobile and admin applications')
        .setVersion(config.get('APP_VERSION', { infer: true }))
        .addBearerAuth()
        .build(),
    );
    SwaggerModule.setup('docs', app, document);
  }

  const port = config.get('PORT', { infer: true });
  await app.listen(port, '0.0.0.0');
  Logger.log(`Bsheel API listening on port ${port}`, 'Bootstrap');
}
await bootstrap();
