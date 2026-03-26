# ── Build Stage ──────────────────────────────────────────────────────
FROM node:25-alpine AS builder

WORKDIR /app

# Install dependencies first (layer cache)
COPY package.json package-lock.json* ./
RUN npm ci --ignore-scripts

# Copy source and build
COPY tsconfig.json ./
COPY src/ ./src/
RUN npm run build

# ── Production Stage ────────────────────────────────────────────────
FROM node:25-alpine

WORKDIR /app

# Install production dependencies only
COPY package.json package-lock.json* ./
RUN npm ci --omit=dev --ignore-scripts && npm cache clean --force

# Copy compiled output
COPY --from=builder /app/dist ./dist
COPY config/ ./config/

# Run as non-root for security
RUN addgroup -S openbrain && adduser -S openbrain -G openbrain
USER openbrain

# Expose ports: API (8000) and MCP (8080)
EXPOSE 8000 8080

# Health check
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD wget -qO- http://localhost:8000/health || exit 1

# Run
CMD ["node", "dist/index.js"]
