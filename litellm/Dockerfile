# ==========================================
# Build Arguments
# ==========================================
ARG DEBIAN_TRIXIE_DIGEST
ARG PRISMA_VERSION

# ==========================================
# 1. Builder Stage
# ==========================================
FROM debian:trixie-slim@${DEBIAN_TRIXIE_DIGEST} AS builder

ARG PRISMA_VERSION

ENV DEBIAN_FRONTEND=noninteractive \
    PATH="/opt/venv/bin:$PATH" \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PYTHONDONTWRITEBYTECODE=1

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
    python3 \
    python3-venv \
    python3-pip \
    python3-build \
    nodejs \
    npm \
    git \
    curl \
    ca-certificates \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

RUN python3 -m venv /opt/venv

WORKDIR /app

COPY . .

# ── pip install (requirements.txt / pyproject.toml 자동 탐색) ──────────────
RUN set -eux; \
    req_file=""; \
    for candidate in requirements.txt litellm/requirements.txt requirements/requirements.txt; do \
      if [ -f "$candidate" ]; then req_file="$candidate"; break; fi; \
    done; \
    if [ -n "$req_file" ]; then \
      pip install --no-binary=orjson,uvloop,pydantic-core,watchfiles,httptools,MarkupSafe,tiktoken,cryptography,rpds-py \
        -r "$req_file" || \
      pip install -r "$req_file"; \
    elif [ -f pyproject.toml ]; then \
      pip install . || pip install -e .; \
    else \
      echo "ERROR: requirements.txt 또는 pyproject.toml 파일을 찾지 못했습니다." >&2; \
      exit 1; \
    fi

# ── [FIX #1, #2] 중복 설치 제거 + npm cache clean 제거 ────────────────────
# 버전 고정된 단일 RUN 만 유지, --mount=type=cache 와 cache clean 은 함께 쓰지 않음
RUN --mount=type=cache,target=/root/.npm,sharing=locked \
    npm install -g "prisma@${PRISMA_VERSION}" --prefer-offline --no-audit --fund=false

# ── Prisma generate ───────────────────────────────────────────────────────
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

# ── Admin UI 빌드 + wheel 패키징 ──────────────────────────────────────────
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

# ── [FIX #3] useradd 를 COPY 보다 먼저 실행 ──────────────────────────────
RUN groupadd -r litellm && \
    useradd -r -g litellm -d /home/litellm -m -s /usr/sbin/nologin litellm

# ── builder 아티팩트 복사 ─────────────────────────────────────────────────
COPY --from=builder /opt/venv /opt/venv
COPY --from=builder /root/.cache/prisma-python /home/litellm/.cache/prisma-python
COPY --from=builder /app /app

# ── 권한 설정 ─────────────────────────────────────────────────────────────
RUN test -f /usr/lib/x86_64-linux-gnu/libjemalloc.so.2 && \
    chmod +x -R /home/litellm/.cache/prisma-python || true && \
    chown -R litellm:litellm /home/litellm /app && \
    ldconfig && \
    find /opt/venv -type d -path "*/tornado/test" -exec rm -rf {} + || true && \
    test -f docker/prod_entrypoint.sh && \
    if [ -f docker/entrypoint.sh ]; then chmod +x docker/entrypoint.sh; fi && \
    chmod +x docker/prod_entrypoint.sh

EXPOSE 4000/tcp

USER litellm

ENTRYPOINT ["/usr/bin/tini", "--", "docker/prod_entrypoint.sh"]
CMD ["--port", "4000"]
