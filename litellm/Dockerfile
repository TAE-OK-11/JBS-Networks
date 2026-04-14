# syntax=docker/dockerfile:1.7

ARG BASE_IMAGE=debian:trixie
FROM ${BASE_IMAGE} AS builder

ARG CPU_FLAGS="-O3 -march=znver3 -mtune=znver3 -mavx2 -mfma -mbmi2 -madx -fPIC -fstack-protector-strong -D_FORTIFY_SOURCE=2 -pipe"
ARG LTO_FLAGS="-flto=full -fuse-ld=lld"
ARG RUSTFLAGS_NATIVE="-C target-cpu=znver3 -C opt-level=3 -C linker=clang -C link-arg=-fuse-ld=lld -C lto=fat -C codegen-units=1"
ARG NPM_VERSION=11.12.1
ARG PRISMA_ENGINE_VERSION=latest

ENV DEBIAN_FRONTEND=noninteractive \
    CC=clang \
    CXX=clang++ \
    CFLAGS="${CPU_FLAGS} ${LTO_FLAGS}" \
    CXXFLAGS="${CPU_FLAGS} ${LTO_FLAGS}" \
    CPPFLAGS="${CPU_FLAGS}" \
    LDFLAGS="${LTO_FLAGS} -Wl,--as-needed -Wl,-O1 -Wl,--sort-common" \
    RUSTFLAGS="${RUSTFLAGS_NATIVE}" \
    UV_PROJECT_ENVIRONMENT=/opt/venv \
    UV_LINK_MODE=copy \
    XDG_CACHE_HOME=/app/.cache \
    PRISMA_BINARY_CACHE_DIR=/app/.cache/prisma-python/binaries \
    PRISMA_CLI_QUERY_ENGINE_TYPE=binary \
    PRISMA_CLIENT_ENGINE_TYPE=binary \
    PATH="/opt/venv/bin:/root/.cargo/bin:/root/.local/bin:${PATH}" \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    ca-certificates \
    curl \
    git \
    jq \
    sed \
    findutils \
    coreutils \
    build-essential \
    pkg-config \
    python3 \
    python3-dev \
    python3-venv \
    clang \
    lld \
    llvm \
    rustc \
    cargo \
    nodejs \
    npm \
    openssl \
    libssl-dev \
    libsndfile1 \
    libatomic1 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

RUN python3 -m venv /opt/venv \
    && /opt/venv/bin/pip install --no-cache-dir --upgrade pip setuptools wheel build uv \
    && npm install -g npm@${NPM_VERSION} prisma

# dependency metadata first for cache efficiency
COPY pyproject.toml uv.lock ./
COPY enterprise/pyproject.toml enterprise/
COPY litellm-proxy-extras/pyproject.toml litellm-proxy-extras/
COPY package.json package-lock.json ./

# install third-party dependencies only
RUN uv sync --frozen --no-install-project --no-install-workspace --no-default-groups --no-editable \
    --extra proxy \
    --extra proxy-runtime \
    --extra extra_proxy \
    --extra semantic-router \
    --python /opt/venv/bin/python

# now copy full source tree
COPY . .

# normalize scripts
RUN sed -i 's/\r$//' docker/build_admin_ui.sh \
    && sed -i 's/\r$//' docker/entrypoint.sh \
    && sed -i 's/\r$//' docker/prod_entrypoint.sh \
    && chmod +x docker/build_admin_ui.sh docker/entrypoint.sh docker/prod_entrypoint.sh

# build admin ui
RUN ./docker/build_admin_ui.sh

# install project + workspace packages
RUN uv sync --frozen --no-default-groups --no-editable \
    --extra proxy \
    --extra proxy-runtime \
    --extra extra_proxy \
    --extra semantic-router \
    --python /opt/venv/bin/python

# generate prisma client using repo-root schema
RUN test -f ./schema.prisma \
    && prisma generate --schema=./schema.prisma

# optional cleanup in builder to reduce copied size
RUN find /opt/venv -type d -path "*/test*" -prune -exec rm -rf {} + || true \
    && find /opt/venv -type d -path "*/tests*" -prune -exec rm -rf {} + || true \
    && find /opt/venv -type d -path "*/__pycache__" -prune -exec rm -rf {} + || true \
    && npm cache clean --force || true


FROM ${BASE_IMAGE} AS runtime

ENV DEBIAN_FRONTEND=noninteractive \
    PATH="/opt/venv/bin:${PATH}" \
    XDG_CACHE_HOME=/app/.cache \
    PRISMA_BINARY_CACHE_DIR=/app/.cache/prisma-python/binaries \
    PRISMA_CLI_QUERY_ENGINE_TYPE=binary \
    PRISMA_CLIENT_ENGINE_TYPE=binary \
    PYTHONOPTIMIZE=2 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    LD_PRELOAD=/usr/lib/x86_64-linux-gnu/libjemalloc.so.2 \
    MALLOC_CONF=metadata_thp:auto,percpu_arena:percpu,tcache_max:32768,dirty_decay_ms:30000,muzzy_decay_ms:30000

RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    ca-certificates \
    python3 \
    openssl \
    nodejs \
    npm \
    libsndfile1 \
    libatomic1 \
    libjemalloc2 \
    tzdata \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY --from=builder /opt/venv /opt/venv
COPY --from=builder /app /app

RUN chmod +x docker/entrypoint.sh docker/prod_entrypoint.sh \
    && chmod -R +x /app/.cache/prisma-python || true \
    && find /opt/venv -type d -path "*/tornado/test" -exec rm -rf {} + || true

EXPOSE 4000

ENTRYPOINT ["/bin/sh", "-c", "exec docker/prod_entrypoint.sh \"$@\"", "--"]
CMD ["--port", "4000"]
