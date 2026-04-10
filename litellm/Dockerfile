# ==========================================
# 1. Builder Stage
# ==========================================
ARG CPU_FLAGS="-O3 -march=znver3 -mtune=znver3 -mavx2 -mfma -mbmi2 -madx -fPIC -fstack-protector-strong -D_FORTIFY_SOURCE=2 -pipe"
ARG LTO_FLAGS="-flto=thin -fuse-ld=lld"

FROM debian:trixie AS builder
ARG CPU_FLAGS
ARG LTO_FLAGS

# 엔진 다운로드 위치 강제 고정
ENV PRISMA_PY_BINARY_CACHE_DIR=/opt/prisma_binaries \
    PRISMA_CLI_QUERY_ENGINE_TYPE=binary \
    PRISMA_CLIENT_ENGINE_TYPE=binary \
    DEBIAN_FRONTEND=noninteractive \
    CC="clang" \
    CXX="clang++" \
    CFLAGS="${CPU_FLAGS} ${LTO_FLAGS}" \
    CXXFLAGS="${CPU_FLAGS} ${LTO_FLAGS}" \
    LDFLAGS="${LTO_FLAGS} -Wl,--as-needed -Wl,-O1 -Wl,--sort-common" \
    PATH="/opt/venv/bin:$PATH" \
    RUSTFLAGS="-C target-cpu=znver3 -C opt-level=3 -C linker=clang -C link-arg=-fuse-ld=lld -C lto=thin"

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential cmake wget curl git pkg-config \
    python3 python3-pip python3-venv python3-dev \
    nodejs npm rustc cargo golang-go \
    libssl-dev llvm clang lld libatomic1 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

RUN python3 -m venv /opt/venv && \
    pip install --no-cache-dir --upgrade pip build wheel setuptools

COPY requirements.txt .
RUN pip install --no-cache-dir --no-binary=orjson,uvloop,pydantic-core,watchfiles,httptools,MarkupSafe,tiktoken,cryptography,rpds-py -r requirements.txt || \
    pip install --no-cache-dir -r requirements.txt

# Prisma 글로벌 설치
RUN npm install -g prisma && \
    mkdir -p ${PRISMA_PY_BINARY_CACHE_DIR}

COPY . .

# 스키마 기반 코드 생성 및 엔진 다운로드
RUN prisma generate --schema=./litellm/proxy/schema.prisma

# Admin UI 컴파일
RUN sed -i 's/\r$//' docker/build_admin_ui.sh && \
    chmod +x docker/build_admin_ui.sh && \
    ./docker/build_admin_ui.sh && \
    rm -rf dist/* && python3 -m build && \
    pip install dist/*.whl

# ==========================================
# 2. Runtime Stage
# ==========================================
FROM debian:trixie AS runtime

# 중요: 런타임 엔진 환경 변수 통일 및 Jemalloc 주입 보류
ENV PRISMA_PY_BINARY_CACHE_DIR=/opt/prisma_binaries \
    PRISMA_CLI_QUERY_ENGINE_TYPE=binary \
    PRISMA_CLIENT_ENGINE_TYPE=binary \
    DEBIAN_FRONTEND=noninteractive \
    PATH="/opt/venv/bin:$PATH" \
    PYTHONOPTIMIZE=2

# 런타임 필수 라이브러리 설치
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 \
    libsndfile1 \
    libatomic1 \
    nodejs \
    ca-certificates \
    libjemalloc2 \
    openssl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# 파일 시스템 이관
COPY --from=builder /opt/venv /opt/venv
COPY --from=builder /opt/prisma_binaries /opt/prisma_binaries
COPY --from=builder /app /app

# 권한 부여 및 시스템 정리
RUN chmod +x -R /opt/prisma_binaries || true && \
    /sbin/ldconfig && \
    find /opt/venv -type d -path "*/tornado/test" -exec rm -rf {} + || true && \
    chmod +x docker/entrypoint.sh docker/prod_entrypoint.sh

EXPOSE 4000/tcp

# 핵심 트릭: 엔트리포인트 실행 직전에만 LD_PRELOAD를 주입하여 
# Prisma의 서브프로세스 엔진 초기화 충돌을 방지합니다.
ENTRYPOINT ["/bin/sh", "-c", "export LD_PRELOAD=/usr/lib/x86_64-linux-gnu/libjemalloc.so.2 && export MALLOC_CONF='background_thread:true,metadata_thp:auto,percpu_arena:percpu,tcache_max:32768,dirty_decay_ms:30000,muzzy_decay_ms:30000' && exec docker/prod_entrypoint.sh \"$@\"", "--"]
CMD ["--port", "4000"]
