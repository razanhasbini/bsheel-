FROM node:26-alpine AS dependencies
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci

FROM dependencies AS build
COPY nest-cli.json tsconfig.json tsconfig.build.json ./
COPY src ./src
RUN npm run build

FROM node:26-alpine AS runtime
ENV NODE_ENV=production
WORKDIR /app
# ffmpeg decodes video proof into still frames for AI verification (#47).
# Alpine's own musl build rather than an npm-bundled binary, which ships
# glibc builds that do not run here. Without it the worker still functions:
# video proof escalates to a human, as it did before frame extraction.
RUN apk add --no-cache ffmpeg
RUN addgroup -S bsheel && adduser -S -G bsheel bsheel
COPY package.json package-lock.json ./
RUN npm ci --omit=dev && npm cache clean --force
COPY --from=build /app/dist ./dist
COPY migrations ./migrations
COPY scripts ./scripts
USER bsheel
EXPOSE 3000
CMD ["node", "--enable-source-maps", "dist/main.js"]

