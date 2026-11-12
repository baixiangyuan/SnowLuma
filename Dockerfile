# syntax=docker/dockerfile:1

ARG NODE_VERSION=24.22.1

# ---------- build ----------
FROM node:${NODE_VERSION}-bookworm-slim AS build

ENV PNPM_HOME=/pnpm
ENV PATH=/pnpm:$PATH
ENV CI=1

RUN corepack enable && corepack prepare pnpm@11.25.0 --activate

WORKDIR /src

# Manifests first so the dependency layer caches independently of source edits.
COPY pnpm-lock.yaml pnpm-workspace.yaml package.json .npmrc ./
COPY packages ./packages

RUN pnpm install --frozen-lockfile

COPY . .

ARG TARGETARCH
RUN case "$TARGETARCH" in \
      amd64) target=linux-x64 ;; \
      arm64) target=linux-arm64 ;; \
      *) echo "unsupported TARGETARCH: $TARGETARCH" >&2; exit 1 ;; \
    esac; \
    SNOWLUMA_TARGET="$target" pnpm run build:all && \
    pnpm check:release-layout

# ---------- runtime ----------
FROM node:${NODE_VERSION}-bookworm-slim AS runtime

LABEL org.opencontainers.image.title="SnowLuma" \
      org.opencontainers.image.description="Next Remote Protocol Framework - OneBot v11 bridge for QQ" \
      org.opencontainers.image.licenses="SEE LICENSE IN LICENSE"

ENV NODE_ENV=production
ENV SNOWLUMA_WEBUI_HOST=0.0.0.0
ENV SNOWLUMA_WEBUI_PORT=5099

WORKDIR /app

COPY --from=build /src/dist ./
COPY --from=build /src/LICENSE /licenses/LICENSE
COPY --from=build /src/EULA.md /licenses/EULA.md
COPY --from=build /src/PRIVACY.md /licenses/PRIVACY.md

RUN mkdir -p /app/data /app/config && chown -R node:node /app /licenses

USER node

EXPOSE 5099

VOLUME ["/app/data", "/app/config"]

HEALTHCHECK --interval=30s --timeout=5s --start-period=40s --retries=3 \
  CMD ["node", "-e", "fetch('http://127.0.0.1:'+(process.env.SNOWLUMA_WEBUI_PORT||5099)+'/').then(r=>process.exit(r.status<500?0:1)).catch(()=>process.exit(1))"]

CMD ["node", "index.mjs"]