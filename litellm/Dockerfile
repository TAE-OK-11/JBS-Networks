# syntax=docker/dockerfile:1.7

ARG LITELLM_BUILD_IMAGE=python:3.11-slim-bookworm
ARG LITELLM_RUNTIME_IMAGE=python:3.11-slim-bookworm
ARG UV_IMAGE=ghcr.io/astral-sh/uv:0.10.9@sha256:10902f58a1606787602f303954cea099626a4adb02acbac4c69920fe9d278f82

FROM ${UV_IMAGE} AS uvbin

FROM ${LITELLM_BUILD_IMAGE} AS builder

ARG CPU_FLAGS="-O3 -march=znver3 -mtune=znver3 -mavx2 -mfma -mbmi2 -madx -fPIC -fstack-protector-strong -D_FORTIFY_SOURCE=2 -pipe"
ARG LTO_FLAGS="-flto=full -fuse-ld=lld"
ARG RUSTFLAGS_NATIVE="-C target-cpu=znver3 -C opt-level=3 -C linker=clang -C link-arg=-fuse-ld=lld -C lto=fat -C codegen-units=1"

WORKDIR /app

COPY --from=uvbin /uv /usr/local/bin/uv
COPY --from=uvbin /uvx /usr/local/bin/uvx

RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    ca-certificates \
    gcc \
    g++ \
    clang \
    lld \
    make \
    pkg-config \
    python3-dev \
    curl \
    git \
    nodejs \
    npm \
    libsndfile1 \
    libsndfile1-dev \
    libssl-dev \
    openssl \
    libatomic1 \
    && rm -rf /var/lib/apt/lists/*

ENV CC=clang \
    CXX=clang++ \
    CFLAGS="${CPU_FLAGS} ${LTO_FLAGS}" \
    CXXFLAGS="${CPU_FLAGS} ${LTO_FLAGS}" \
    CPPFLAGS="${CPU_FLAGS}" \
    LDFLAGS="${LTO_FLAGS} -Wl,--as-needed -Wl,-O1 -Wl,--sort-common" \
    RUSTFLAGS="${RUSTFLAGS_NATIVE}" \
    PRISMA_BINARY_CACHE_DIR=/app/.cache/prisma-python/binaries \
    UV_PROJECT_ENVIRONMENT=/app/.venv \
    UV_LINK_MODE=copy \
    XDG_CACHE_HOME=/app/.cache \
    PRISMA_CLI_QUERY_ENGINE_TYPE=binary \
    PRISMA_CLIENT_ENGINE_TYPE=binary \
    PATH="/app/.venv/bin:${PATH}" \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

# Copy dependency metadata first for layer caching
COPY pyproject.toml uv.lock ./
COPY enterprise/pyproject.toml enterprise/
COPY litellm-proxy-extras/pyproject.toml litellm-proxy-extras/

# Install third-party dependencies
RUN uv sync --frozen --no-install-project --no-install-workspace --no-default-groups --no-editable \
    --extra proxy \
    --extra proxy-runtime \
    --extra extra_proxy \
    --extra semantic-router \
    --python python3

# Copy full source tree
COPY . .

# Install project + workspace packages
RUN uv sync --frozen --no-default-groups --no-editable \
    --extra proxy \
    --extra proxy-runtime \
    --extra extra_proxy \
    --extra semantic-router \
    --python python3

# Generate Prisma client
RUN test -f ./schema.prisma && prisma generate --schema=./schema.prisma

# Normalize scripts
RUN sed -i 's/\r$//' docker/entrypoint.sh \
    && chmod +x docker/entrypoint.sh \
    && sed -i 's/\r$//' docker/prod_entrypoint.sh \
    && chmod +x docker/prod_entrypoint.sh

# Optional cleanup
RUN find /app/.venv -type d -name "__pycache__" -prune -exec rm -rf {} + || true


FROM ${LITELLM_RUNTIME_IMAGE} AS runtime

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    nodejs \
    npm \
    libsndfile1 \
    libatomic1 \
    libjemalloc2 \
    openssl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

ENV PRISMA_BINARY_CACHE_DIR=/app/.cache/prisma-python/binaries \
    XDG_CACHE_HOME=/app/.cache \
    PATH="/app/.venv/bin:${PATH}" \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PYTHONOPTIMIZE=2 \
    LD_PRELOAD=/usr/lib/x86_64-linux-gnu/libjemalloc.so.2 \
    MALLOC_CONF=metadata_thp:auto,percpu_arena:percpu,tcache_max:32768,dirty_decay_ms:30000,muzzy_decay_ms:30000

COPY --from=builder /app /app

EXPOSE 4000/tcp

ENTRYPOINT ["docker/prod_entrypoint.sh"]
CMD ["--port", "4000"]
