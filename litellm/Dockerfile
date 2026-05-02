# syntax=docker/dockerfile:1.7
#
# JBS Networks — LiteLLM v1.83.x compatible build
# Target: AMD Zen3/EPYC, Clang+ThinLTO, jemalloc THP
# Upstream reference: BerriAI/litellm@litellm_internal_staging (v1.83.9)
#

ARG LITELLM_BUILD_IMAGE=python:3.13-slim-bookworm
ARG LITELLM_RUNTIME_IMAGE=python:3.13-slim-bookworm
ARG UV_IMAGE=ghcr.io/astral-sh/uv:0.10.9@sha256:10902f58a1606787602f303954cea099626a4adb02acbac4c69920fe9d278f82

FROM ${UV_IMAGE} AS uvbin

# ---------------------------------------------------------------------------
# Builder stage
# ---------------------------------------------------------------------------
FROM ${LITELLM_BUILD_IMAGE} AS builder

ARG CPU_FLAGS="-O3 -march=znver3 -mtune=znver3 -mavx2 -mfma -mbmi2 -madx -fPIC -fstack-protector-strong -D_FORTIFY_SOURCE=2 -pipe"
ARG LTO_FLAGS="-flto=full -fuse-ld=lld"
ARG RUSTFLAGS_NATIVE="-C target-cpu=znver3 -C opt-level=3 -C linker=clang -C link-arg=-fuse-ld=lld -C lto=fat -C codegen-units=1"

WORKDIR /app

COPY --from=uvbin /uv /usr/local/bin/uv
COPY --from=uvbin /uvx /usr/local/bin/uvx

# NodeSource Node.js 20 LTS (Debian bookworm의 기본 nodejs 18은 Next.js 15 admin UI 빌드에
# 경계선에 있음 — 20 LTS로 통일)
RUN apt-get update && apt-get install -y --no-install-recommends \
        curl ca-certificates gnupg \
    && mkdir -p /etc/apt/keyrings \
    && curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
        | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg \
    && echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_20.x nodistro main" \
        > /etc/apt/sources.list.d/nodesource.list \
    && apt-get update && apt-get install -y --no-install-recommends \
        bash \
        gcc \
        g++ \
        clang \
        lld \
        make \
        pkg-config \
        python3-dev \
        git \
        nodejs \
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
    UV_COMPILE_BYTECODE=1 \
    XDG_CACHE_HOME=/app/.cache \
    PRISMA_CLI_QUERY_ENGINE_TYPE=binary \
    PRISMA_CLIENT_ENGINE_TYPE=binary \
    PATH="/app/.venv/bin:${PATH}" \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

# ---- layer 1: dependency metadata only (cache-friendly) --------------------
COPY pyproject.toml uv.lock ./
COPY enterprise/pyproject.toml enterprise/
COPY litellm-proxy-extras/pyproject.toml litellm-proxy-extras/

RUN uv sync --frozen --no-install-project --no-install-workspace --no-default-groups --no-editable \
    --extra proxy \
    --extra proxy-runtime \
    --extra extra_proxy \
    --extra semantic-router \
    --python python3

# ---- layer 2: full source tree --------------------------------------------
COPY . .

# ---- layer 3: Admin UI build (v1.83+ 신규 필수 단계) ----------------------
# build_admin_ui.sh 는 UI/ 아래 Next.js 앱을 빌드해서 litellm/proxy/_experimental/out
# 으로 배치함. 이게 없으면 관리자 UI (/ui) 가 404가 됨.
RUN sed -i 's/\r$//' docker/build_admin_ui.sh \
    && chmod +x docker/build_admin_ui.sh \
    && ./docker/build_admin_ui.sh

# ---- layer 4: project + workspace packages --------------------------------
RUN uv sync --frozen --no-default-groups --no-editable \
    --extra proxy \
    --extra proxy-runtime \
    --extra extra_proxy \
    --extra semantic-router \
    --python python3

# ---- layer 5: Prisma client ------------------------------------------------
RUN test -f ./schema.prisma && prisma generate --schema=./schema.prisma

# ---- layer 6: normalize entrypoint scripts --------------------------------
RUN sed -i 's/\r$//' docker/entrypoint.sh \
    && chmod +x docker/entrypoint.sh \
    && sed -i 's/\r$//' docker/prod_entrypoint.sh \
    && chmod +x docker/prod_entrypoint.sh

# ---- layer 7: cleanup ------------------------------------------------------
RUN find /app/.venv -type d -name "__pycache__" -prune -exec rm -rf {} + || true \
    && find /app/.venv -type d -name "tests" -prune -exec rm -rf {} + || true \
    && find /app/.venv -type d -name "test" -prune -exec rm -rf {} + || true


# ---------------------------------------------------------------------------
# Runtime stage
# ---------------------------------------------------------------------------
FROM ${LITELLM_RUNTIME_IMAGE} AS runtime

# Node.js 20 LTS + supervisor (v1.83+ prod_entrypoint.sh 가 supervisord 사용)
RUN apt-get update && apt-get install -y --no-install-recommends \
        curl ca-certificates gnupg \
    && mkdir -p /etc/apt/keyrings \
    && curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
        | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg \
    && echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_20.x nodistro main" \
        > /etc/apt/sources.list.d/nodesource.list \
    && apt-get update && apt-get install -y --no-install-recommends \
        nodejs \
        libsndfile1 \
        libatomic1 \
        libjemalloc2 \
        openssl \
        supervisor \
        tzdata \
    && npm install -g npm@11.12.1 \
    && npm cache clean --force \
    && apt-get purge -y --auto-remove curl gnupg \
    && rm -rf /var/lib/apt/lists/* /root/.npm

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

# 이미지 슬림화 — tornado 테스트 리소스 제거 (공식 Dockerfile 과 동일 처리)
RUN find /app/.venv -type f -path "*/tornado/test/*" -delete \
    && find /app/.venv -type d -path "*/tornado/test" -delete

# supervisord 설정 (v1.83+ 필수)
COPY docker/supervisord.conf /etc/supervisord.conf

EXPOSE 4000/tcp

ENTRYPOINT ["docker/prod_entrypoint.sh"]
CMD ["--port", "4000"]
