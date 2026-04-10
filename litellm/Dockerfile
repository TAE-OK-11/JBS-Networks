# ==========================================
# 1. Builder Stage
# ==========================================
# Zen3 전용 최적화 플래그 및 Thin LTO 적용
ARG CPU_FLAGS="-O3 -march=znver3 -mtune=znver3 -mavx2 -mfma -mbmi2 -madx -fPIC -fstack-protector-strong -D_FORTIFY_SOURCE=2 -pipe"
ARG LTO_FLAGS="-flto=thin -fuse-ld=lld"

FROM debian:trixie AS builder
ARG CPU_FLAGS
ARG LTO_FLAGS

# Prisma 엔진 다운로드 경로 고정 및 컴파일 환경 변수
ENV PRISMA_PY_BINARY_CACHE_DIR=/opt/prisma_binaries \
    DEBIAN_FRONTEND=noninteractive \
    CC="clang" \
    CXX="clang++" \
    CFLAGS="${CPU_FLAGS} ${LTO_FLAGS}" \
    CXXFLAGS="${CPU_FLAGS} ${LTO_FLAGS}" \
    LDFLAGS="${LTO_FLAGS} -Wl,--as-needed -Wl,-O1 -Wl,--sort-common" \
    PATH="/opt/venv/bin:$PATH" \
    RUSTFLAGS="-C target-cpu=znver3 -C opt-level=3 -C linker=clang -C link-arg=-fuse-ld=lld -C lto=thin"

# 빌드 필수 도구 설치 (libatomic1, libssl-dev 포함)
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential cmake wget curl git pkg-config \
    python3 python3-pip python3-venv python3-dev \
    nodejs npm rustc cargo golang-go \
    libssl-dev llvm clang lld libatomic1 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# 파이썬 가상환경 생성
RUN python3 -m venv /opt/venv && \
    pip install --no-cache-dir --upgrade pip build wheel setuptools

# 고성능 Rust/C 모듈 강제 컴파일 빌드
COPY requirements.txt .
RUN pip install --no-cache-dir --no-binary=orjson,uvloop,pydantic-core,watchfiles,httptools,MarkupSafe,tiktoken,cryptography,rpds-py -r requirements.txt || \
    pip install --no-cache-dir -r requirements.txt

# Prisma 설치 및 엔진 캐시 디렉토리 생성
RUN npm install -g prisma && \
    mkdir -p ${PRISMA_PY_BINARY_CACHE_DIR}

COPY . .

# 데이터베이스 ORM 생성 (이때 엔진이 다운로드 됨)
RUN prisma generate --schema=./litellm/proxy/schema.prisma

# Admin UI 컴파일 및 최종 패키징
RUN sed -i 's/\r$//' docker/build_admin_ui.sh && \
    chmod +x docker/build_admin_ui.sh && \
    ./docker/build_admin_ui.sh && \
    rm -rf dist/* && python3 -m build && \
    pip install dist/*.whl

# ==========================================
# 2. Runtime Stage
# ==========================================
# 안정성 확보를 위해 Full Debian 이미지 사용
FROM debian:trixie AS runtime

# Prisma 엔진 경로 유지 및 Jemalloc 튜닝
ENV PRISMA_PY_BINARY_CACHE_DIR=/opt/prisma_binaries \
    DEBIAN_FRONTEND=noninteractive \
    PATH="/opt/venv/bin:$PATH" \
    LD_PRELOAD="/usr/lib/x86_64-linux-gnu/libjemalloc.so.2" \
    MALLOC_CONF="background_thread:true,metadata_thp:auto,percpu_arena:percpu,tcache_max:32768,dirty_decay_ms:30000,muzzy_decay_ms:30000" \
    PYTHONOPTIMIZE=2

# 런타임 필수 라이브러리 (openssl 반드시 포함)
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

# 빌드 결과물 및 Prisma 엔진 이관
COPY --from=builder /opt/venv /opt/venv
COPY --from=builder /opt/prisma_binaries /opt/prisma_binaries
COPY --from=builder /app /app

# 엔진 바이너리 실행 권한 보장 및 정리 작업
RUN chmod +x -R /opt/prisma_binaries || true && \
    /sbin/ldconfig && \
    find /opt/venv -type d -path "*/tornado/test" -exec rm -rf {} + || true && \
    chmod +x docker/entrypoint.sh docker/prod_entrypoint.sh

EXPOSE 4000/tcp
ENTRYPOINT ["docker/prod_entrypoint.sh"]
CMD ["--port", "4000"]
