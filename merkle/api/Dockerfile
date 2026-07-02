FROM node:22-slim

# Enable corepack; the pnpm version is pinned via package.json "packageManager"
# so the image matches the pnpm major that generated pnpm-lock.yaml (v9 →
# lockfileVersion 9.0). Do NOT use `pnpm@latest` here: a pnpm 10 roll made
# `--frozen-lockfile` reject the v9 lockfile, breaking a previously-green build.
RUN corepack enable

WORKDIR /app

COPY package.json pnpm-lock.yaml ./
# `corepack pnpm` resolves the version from package.json "packageManager".
RUN corepack pnpm install --frozen-lockfile --prod=false

COPY . .

EXPOSE 3002

CMD ["pnpm", "start"]
