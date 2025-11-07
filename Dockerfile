# syntax=docker/dockerfile:1

# ------------------------------------------------------
#  Base image
# ------------------------------------------------------
  FROM node:22-alpine AS base
  WORKDIR /app
  RUN apk add --no-cache libc6-compat
  ENV NODE_ENV=production
  
  # Enable corepack to use pnpm
  RUN corepack enable pnpm
  
  # ------------------------------------------------------
  #  Dependencies (build + dev)
  # ------------------------------------------------------
  FROM base AS deps
  WORKDIR /app
  
  # Copy only lock + manifest for dependency layer caching
  COPY pnpm-lock.yaml package.json .npmrc* ./
  
  # Install all dependencies (including dev) for build
  RUN pnpm install --frozen-lockfile
  
  # ------------------------------------------------------
  #  Build stage
  # ------------------------------------------------------
  FROM base AS builder
  WORKDIR /app
  
  # Copy dependencies from deps stage
  COPY --from=deps /app/node_modules ./node_modules
  COPY . .
  
  # Build Next.js
  RUN pnpm run build
  
  # ------------------------------------------------------
  #  Production dependencies (runtime only)
  # ------------------------------------------------------
  FROM base AS prod-deps
  WORKDIR /app
  
  COPY pnpm-lock.yaml package.json .npmrc* ./
  RUN pnpm install --frozen-lockfile --prod
  
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
  COPY --from=builder /app/public ./public
  COPY --from=builder /app/.next/standalone ./
  COPY --from=builder /app/.next/static ./.next/static
  COPY --from=prod-deps /app/node_modules ./node_modules
  
  USER nextjs
  EXPOSE 3000
  
  CMD ["node", "server.js"]
  