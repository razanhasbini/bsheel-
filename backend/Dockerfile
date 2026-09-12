# syntax=docker/dockerfile:1.7
#
# The two `npm ci` steps below pull the whole dependency tree twice over a
# link that is not always fast. On a slow connection npm's registry socket
# goes idle mid-download and the build dies with EIDLETIMEOUT after twenty
# minutes of work — which looks like a broken lockfile and is not one.
#
# So both steps get patience and a cache. The retry settings let a stalled
# socket recover instead of failing the layer, and the BuildKit cache mount
# keeps the npm store between builds so a rebuild after a code change
# re-downloads nothing at all.
FROM node:26-alpine AS dependencies
WORKDIR /app
# 5 minutes before a quiet socket is considered dead, and five attempts with
# a widening backoff. Defaults are 30s and 2, which a congested link can miss.
ENV npm_config_fetch_timeout=300000 \
    npm_config_fetch_retries=5 \
    npm_config_fetch_retry_mintimeout=20000 \
    npm_config_fetch_retry_maxtimeout=180000
COPY package.json package-lock.json ./
RUN --mount=type=cache,target=/root/.npm,sharing=locked npm ci

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
ENV npm_config_fetch_timeout=300000 \
    npm_config_fetch_retries=5 \
    npm_config_fetch_retry_mintimeout=20000 \
    npm_config_fetch_retry_maxtimeout=180000
COPY package.json package-lock.json ./
# `npm cache clean` is gone deliberately: with a cache mount the store never
# lands in the image, so clearing it only threw away the thing that makes the
# next build fast.
RUN --mount=type=cache,target=/root/.npm,sharing=locked npm ci --omit=dev
COPY --from=build /app/dist ./dist
COPY migrations ./migrations
COPY scripts ./scripts
# The curated catalogue. scripts/seed-quests.mjs reads these at runtime, so
# without them a production deploy has the schema and no content — which is
# exactly what an empty Home looked like.
COPY seeds ./seeds
# Brand fonts for the burned-in video band (branded exports, 0050). ffmpeg's
# drawtext needs a font file on disk; the image has none of its own.
COPY assets ./assets
USER bsheel
EXPOSE 3000
CMD ["node", "--enable-source-maps", "dist/main.js"]
