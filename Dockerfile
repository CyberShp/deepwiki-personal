# syntax=docker/dockerfile:1-labs

# Build argument for custom certificates directory
ARG CUSTOM_CERT_DIR="certs"

FROM node:20-alpine3.22 AS node_base

FROM node_base AS node_deps
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --legacy-peer-deps

FROM node_base AS node_builder
WORKDIR /app
COPY --from=node_deps /app/node_modules ./node_modules
# Copy only necessary files for Next.js build
COPY package.json package-lock.json next.config.ts tsconfig.json tailwind.config.js postcss.config.mjs ./
COPY src/ ./src/
COPY public/ ./public/
# Increase Node.js memory limit for build and disable telemetry
ENV NODE_OPTIONS="--max-old-space-size=4096"
ENV NEXT_TELEMETRY_DISABLED=1
RUN NODE_ENV=production npm run build

FROM python:3.11-slim AS py_deps
WORKDIR /api
COPY api/pyproject.toml .
COPY api/poetry.lock .
RUN python -m pip install poetry==2.0.1 --no-cache-dir && \
    poetry config virtualenvs.create true --local && \
    poetry config virtualenvs.in-project true --local && \
    poetry config virtualenvs.options.always-copy --local true && \
    POETRY_MAX_WORKERS=10 poetry install --no-interaction --no-ansi --only main && \
    poetry cache clear --all .

# Pre-cache tiktoken encodings so the image can start offline without hanging
RUN TIKTOKEN_CACHE_DIR=/api/tiktoken_cache \
    .venv/bin/python -c "\
import tiktoken; \
tiktoken.get_encoding('cl100k_base'); \
tiktoken.encoding_for_model('text-embedding-3-small'); \
print('tiktoken encodings cached successfully')"

# Use Python 3.11 as final image
FROM python:3.11-slim

# Set working directory
WORKDIR /app

# Install Node.js and npm
RUN apt-get update && apt-get install -y \
    curl \
    gnupg \
    git \
    ca-certificates \
    && mkdir -p /etc/apt/keyrings \
    && curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg \
    && echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_20.x nodistro main" | tee /etc/apt/sources.list.d/nodesource.list \
    && apt-get update \
    && apt-get install -y nodejs \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Update certificates if custom ones were provided and copied successfully
RUN if [ -n "${CUSTOM_CERT_DIR}" ]; then \
        mkdir -p /usr/local/share/ca-certificates && \
        if [ -d "${CUSTOM_CERT_DIR}" ]; then \
            cp -r ${CUSTOM_CERT_DIR}/* /usr/local/share/ca-certificates/ 2>/dev/null || true; \
            update-ca-certificates; \
            echo "Custom certificates installed successfully."; \
        else \
            echo "Warning: ${CUSTOM_CERT_DIR} not found. Skipping certificate installation."; \
        fi \
    fi

# Point all SSL-aware components at the system CA bundle (includes any custom certs injected above)
ENV SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
ENV REQUESTS_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt
ENV GIT_SSL_CAINFO=/etc/ssl/certs/ca-certificates.crt
ENV NODE_EXTRA_CA_CERTS=/etc/ssl/certs/ca-certificates.crt
ENV CURL_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt

ENV PATH="/opt/venv/bin:$PATH"

# Copy Python dependencies and pre-built tiktoken cache
COPY --from=py_deps /api/.venv /opt/venv
COPY --from=py_deps /api/tiktoken_cache /opt/tiktoken_cache
COPY api/ ./api/

# Copy Node app
COPY --from=node_builder /app/public ./public
COPY --from=node_builder /app/.next/standalone ./
COPY --from=node_builder /app/.next/static ./.next/static

# Expose the port the app runs on
EXPOSE ${PORT:-8001} 3000

# Create a script to run both backend and frontend
RUN echo '#!/bin/bash\n\
# Load environment variables from .env file if it exists\n\
if [ -f .env ]; then\n\
  export $(grep -v "^#" .env | xargs -r)\n\
fi\n\
\n\
# Check for required environment variables\n\
if [ -z "$OPENAI_API_KEY" ] || [ -z "$GOOGLE_API_KEY" ]; then\n\
  echo "Warning: OPENAI_API_KEY and/or GOOGLE_API_KEY environment variables are not set."\n\
  echo "These are required for DeepWiki to function properly."\n\
  echo "You can provide them via a mounted .env file or as environment variables when running the container."\n\
fi\n\
\n\
# Propagate SSL_CERT_FILE to all SSL-aware components (handles runtime cert overrides)\n\
if [ -n "$SSL_CERT_FILE" ]; then\n\
  export REQUESTS_CA_BUNDLE="${REQUESTS_CA_BUNDLE:-$SSL_CERT_FILE}"\n\
  export GIT_SSL_CAINFO="${GIT_SSL_CAINFO:-$SSL_CERT_FILE}"\n\
  export NODE_EXTRA_CA_CERTS="${NODE_EXTRA_CA_CERTS:-$SSL_CERT_FILE}"\n\
  export CURL_CA_BUNDLE="${CURL_CA_BUNDLE:-$SSL_CERT_FILE}"\n\
elif [ -n "$REQUESTS_CA_BUNDLE" ]; then\n\
  export SSL_CERT_FILE="${SSL_CERT_FILE:-$REQUESTS_CA_BUNDLE}"\n\
  export GIT_SSL_CAINFO="${GIT_SSL_CAINFO:-$REQUESTS_CA_BUNDLE}"\n\
  export NODE_EXTRA_CA_CERTS="${NODE_EXTRA_CA_CERTS:-$REQUESTS_CA_BUNDLE}"\n\
  export CURL_CA_BUNDLE="${CURL_CA_BUNDLE:-$REQUESTS_CA_BUNDLE}"\n\
fi\n\
\n\
# Start the API server in the background with the configured port\n\
python -m api.main --port ${PORT:-8001} &\n\
PORT=3000 HOSTNAME=0.0.0.0 node server.js &\n\
wait -n\n\
exit $?' > /app/start.sh && chmod +x /app/start.sh

# Set environment variables
ENV PORT=8001
ENV NODE_ENV=production
ENV SERVER_BASE_URL=http://localhost:${PORT:-8001}
# Point tiktoken at the pre-built cache; override with TIKTOKEN_CACHE_DIR to mount an external cache
ENV TIKTOKEN_CACHE_DIR=/opt/tiktoken_cache

# Create empty .env file (will be overridden if one exists at runtime)
RUN touch .env

# Command to run the application
CMD ["/app/start.sh"]
