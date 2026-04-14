# syntax=docker/dockerfile:1.7

# ==========================================
# 1. Builder Stage
# ==========================================
ARG CPU_FLAGS="-O3 -march=znver3 -mtune=znver3 -mavx2 -mfma -mbmi2 -madx -fPIC -fstack-protector-strong -D_FORTIFY_SOURCE=2 -pipe"
ARG LTO_FLAGS="-flto=thin -fuse-ld=lld"
ARG DEBIAN_TRIXIE_DIGEST="sha256:4ffb3a1511099754cddc70eb1b12e50ffdb67619aa0ab6c13fcd800a78ef7c7a"
ARG PRISMA_VERSION="6.7.0"

FROM debian:trixie-slim@${DEBIAN_TRIXIE_DIGEST} AS builder
ARG CPU_FLAGS
ARG LTO_FLAGS
ARG PRISMA_VERSION

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ENV PRISMA_CLI_QUERY_ENGINE_TYPE=binary \
    PRISMA_CLIENT_ENGINE_TYPE=binary \
    DEBIAN_FRONTEND=noninteractive \
    CC="clang" \
    CXX="clang++" \
    CFLAGS="${CPU_FLAGS} ${LTO_FLAGS}" \
    CXXFLAGS="${CPU_FLAGS} ${LTO_FLAGS}" \
    LDFLAGS="${LTO_FLAGS} -Wl,--as-needed -Wl,-O1 -Wl,--sort-common" \
    PATH="/opt/venv/bin:$PATH" \
    RUSTFLAGS="-C target-cpu=znver3 -C opt-level=3 -C linker=clang -C link-arg=-fuse-ld=lld -C lto=thin" \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_NO_CACHE_DIR=1 \
    PYTHONDONTWRITEBYTECODE=1

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
    build-essential cmake curl git pkg-config \
    python3 python3-pip python3-venv python3-dev \
    nodejs npm rustc cargo \
    libssl-dev llvm clang lld libatomic1 ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

RUN python3 -m venv /opt/venv && \
    pip install --upgrade pip build wheel setuptools

RUN mkdir -p /root/.cache/prisma-python

COPY . .

RUN set -eux; \
    req_file=""; \
    for candidate in requirements.txt litellm/requirements.txt requirements/requirements.txt; do \
      if [ -f "$candidate" ]; then req_file="$candidate"; break; fi; \
    done; \
    if [ -n "$req_file" ]; then \
      pip install --no-binary=orjson,uvloop,pydantic-core,watchfiles,httptools,MarkupSafe,tiktoken,cryptography,rpds-py -r "$req_file" || \
      pip install -r "$req_file"; \
    elif [ -f pyproject.toml ]; then \
      pip install .; \
    else \
      echo "ERROR: requirements.txt 또는 pyproject.toml 파일을 찾지 못했습니다." >&2; \
      exit 1; \
    fi

RUN --mount=type=cache,target=/root/.npm,sharing=locked \
    npm install -g "prisma@${PRISMA_VERSION}" --prefer-offline --no-audit --fund=false && \
    npm cache clean --force

RUN set -eux; \
    schema_path=""; \
    for candidate in litellm/proxy/schema.prisma prisma/schema.prisma schema.prisma; do \
      if [ -f "$candidate" ]; then schema_path="$candidate"; break; fi; \
    done; \
    if [ -z "$schema_path" ]; then \
      echo "ERROR: Prisma schema 파일을 찾지 못했습니다." >&2; \
      exit 1; \
    fi; \
    prisma generate --schema="./${schema_path}"

RUN test -f docker/build_admin_ui.sh && \
    sed -i 's/\r$//' docker/build_admin_ui.sh && \
    chmod +x docker/build_admin_ui.sh && \
    ./docker/build_admin_ui.sh && \
    rm -rf dist/* && python3 -m build && \
    pip install dist/*.whl

# ==========================================
# 2. Runtime Stage
# ==========================================
FROM debian:trixie-slim@${DEBIAN_TRIXIE_DIGEST} AS runtime

ENV PRISMA_CLI_QUERY_ENGINE_TYPE=binary \
    PRISMA_CLIENT_ENGINE_TYPE=binary \
    DEBIAN_FRONTEND=noninteractive \
    PATH="/opt/venv/bin:$PATH" \
    PYTHONOPTIMIZE=2 \
    LD_PRELOAD="/usr/lib/x86_64-linux-gnu/libjemalloc.so.2" \
    MALLOC_CONF="metadata_thp:auto,percpu_arena:percpu,tcache_max:32768,dirty_decay_ms:30000,muzzy_decay_ms:30000" \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PYTHONDONTWRITEBYTECODE=1

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
    python3 \
    libsndfile1 \
    libatomic1 \
    ca-certificates \
    libjemalloc2 \
    openssl \
    nodejs \
    tini \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY --from=builder /opt/venv /opt/venv
COPY --from=builder /root/.cache/prisma-python /home/litellm/.cache/prisma-python
COPY --from=builder /app /app

RUN groupadd -r litellm && useradd -r -g litellm -d /home/litellm -m -s /usr/sbin/nologin litellm

RUN test -f /usr/lib/x86_64-linux-gnu/libjemalloc.so.2 && \
    chmod +x -R /home/litellm/.cache/prisma-python || true && \
    chown -R litellm:litellm /home/litellm /app && \
    ldconfig && \
    find /opt/venv -type d -path "*/tornado/test" -exec rm -rf {} + || true && \
    test -f docker/prod_entrypoint.sh && \
    chmod +x docker/entrypoint.sh docker/prod_entrypoint.sh

EXPOSE 4000/tcp

USER litellm

ENTRYPOINT ["/usr/bin/tini", "--", "docker/prod_entrypoint.sh"]
CMD ["--port", "4000"]
