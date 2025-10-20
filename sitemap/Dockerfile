FROM oven/bun:1 AS base
WORKDIR /app

FROM base AS install
RUN mkdir -p /temp/dev
COPY package.json bun.lock /app
RUN cd /app && bun install --frozen-lockfile


FROM base AS release
COPY --from=install /app/node_modules node_modules

COPY . .

ENTRYPOINT [ "bun", "run", "experiment.ts" ]

