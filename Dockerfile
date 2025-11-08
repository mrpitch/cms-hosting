# syntax=docker/dockerfile:1

# ------------------------------------------------------
#  Base image with pnpm pre-installed
# ------------------------------------------------------
FROM node:22-alpine AS base
WORKDIR /app
RUN apk add --no-cache libc6-compat
ENV NODE_ENV=production

# Pre-install pnpm once in base layer
RUN corepack enable && corepack prepare pnpm@latest --activate

# ------------------------------------------------------
#  Dependencies (build + dev)
# ------------------------------------------------------
FROM base AS deps
WORKDIR /app

# Copy only lock + manifest for dependency layer caching
COPY pnpm-lock.yaml package.json .npmrc* ./

# Install all dependencies with cache mount
RUN --mount=type=cache,id=pnpm,target=/root/.local/share/pnpm/store \
    pnpm install --frozen-lockfile

# ------------------------------------------------------
#  Build stage
# ------------------------------------------------------
FROM base AS builder
WORKDIR /app

# Copy dependencies from deps stage
COPY --from=deps /app/node_modules ./node_modules
COPY . .

# Build Next.js (standalone mode bundles prod deps)
RUN pnpm run build

# ------------------------------------------------------
#  Runner (final production image)
# ------------------------------------------------------
FROM node:22-alpine AS runner
WORKDIR /app
RUN apk add --no-cache libc6-compat

ENV NODE_ENV=production
ENV HOSTNAME="0.0.0.0"
ENV PORT=3000

# Create app user
RUN addgroup --system --gid 1001 nodejs \
 && adduser --system --uid 1001 nextjs

# Copy only required runtime artifacts
# Standalone mode already includes minimal node_modules
COPY --from=builder --chown=nextjs:nodejs /app/public ./public
COPY --from=builder --chown=nextjs:nodejs /app/.next/standalone ./
COPY --from=builder --chown=nextjs:nodejs /app/.next/static ./.next/static

USER nextjs
EXPOSE 3000

CMD ["node", "server.js"]
  