# ==========================================
# 1. Builder Stage
# ==========================================
ARG CPU_FLAGS="-O3 -march=znver3 -mtune=znver3 -mavx2 -mfma -mbmi2 -madx -fPIC -fstack-protector-strong -D_FORTIFY_SOURCE=2 -pipe"
# ✅ 수정됨: thin LTO에서 full LTO로 변경
ARG LTO_FLAGS="-flto=full -fuse-ld=lld"

FROM debian:trixie AS builder
ARG CPU_FLAGS
ARG LTO_FLAGS

# 경로 강제 변경 변수 제거, 기본 경로 활용
# ✅ 수정됨: Rust 컴파일러의 LTO 옵션을 'thin'에서 'fat' (Full LTO)으로 변경
ENV PRISMA_CLI_QUERY_ENGINE_TYPE=binary \
    PRISMA_CLIENT_ENGINE_TYPE=binary \
    DEBIAN_FRONTEND=noninteractive \
    CC="clang" \
    CXX="clang++" \
    CFLAGS="${CPU_FLAGS} ${LTO_FLAGS}" \
    CXXFLAGS="${CPU_FLAGS} ${LTO_FLAGS}" \
    LDFLAGS="${LTO_FLAGS} -Wl,--as-needed -Wl,-O1 -Wl,--sort-common" \
    PATH="/opt/venv/bin:$PATH" \
    RUSTFLAGS="-C target-cpu=znver3 -C opt-level=3 -C linker=clang -C link-arg=-fuse-ld=lld -C lto=fat"

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential cmake wget curl git pkg-config \
    python3 python3-pip python3-venv python3-dev \
    nodejs npm rustc cargo golang-go \
    libssl-dev llvm clang lld libatomic1 ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

RUN python3 -m venv /opt/venv && \
    pip install --no-cache-dir --upgrade pip build wheel setuptools

COPY requirements.txt .
RUN pip install --no-cache-dir --no-binary=orjson,uvloop,pydantic-core,watchfiles,httptools,MarkupSafe,tiktoken,cryptography,rpds-py -r requirements.txt || \
    pip install --no-cache-dir -r requirements.txt

RUN npm install -g prisma

COPY . .

# 스키마 생성 시 /root/.cache/prisma-python 경로에 엔진이 다운로드 됨
RUN prisma generate --schema=./litellm/proxy/schema.prisma

RUN sed -i 's/\r$//' docker/build_admin_ui.sh && \
    chmod +x docker/build_admin_ui.sh && \
    ./docker/build_admin_ui.sh && \
    rm -rf dist/* && python3 -m build && \
    pip install dist/*.whl

# ==========================================
# 2. Runtime Stage
# ==========================================
FROM debian:trixie AS runtime

ENV PRISMA_CLI_QUERY_ENGINE_TYPE=binary \
    PRISMA_CLIENT_ENGINE_TYPE=binary \
    DEBIAN_FRONTEND=noninteractive \
    PATH="/opt/venv/bin:$PATH" \
    PYTHONOPTIMIZE=2

RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 \
    libsndfile1 \
    libatomic1 \
    ca-certificates \
    libjemalloc2 \
    openssl \
    nodejs \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY --from=builder /opt/venv /opt/venv
# 핵심 수정: Prisma 기본 캐시 디렉토리 전체 복사
COPY --from=builder /root/.cache/prisma-python /root/.cache/prisma-python
COPY --from=builder /app /app

# 실행 권한 부여 및 시스템 캐시 갱신
RUN chmod +x -R /root/.cache/prisma-python || true && \
    /sbin/ldconfig && \
    find /opt/venv -type d -path "*/tornado/test" -exec rm -rf {} + || true && \
    chmod +x docker/entrypoint.sh docker/prod_entrypoint.sh

EXPOSE 4000/tcp

ENTRYPOINT ["/bin/sh", "-c", "export LD_PRELOAD=/usr/lib/x86_64-linux-gnu/libjemalloc.so.2 && export MALLOC_CONF='metadata_thp:auto,percpu_arena:percpu,tcache_max:32768,dirty_decay_ms:30000,muzzy_decay_ms:30000' && exec docker/prod_entrypoint.sh \"$@\"", "--"]
CMD ["--port", "4000"]
