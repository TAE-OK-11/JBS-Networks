# ==========================================
# 1. Builder Stage
# ==========================================
ARG CPU_FLAGS="-O3 -march=znver3 -mtune=znver3 -mavx2 -mfma -mbmi2 -madx -fPIC -fstack-protector-strong -D_FORTIFY_SOURCE=2 -pipe"
ARG LTO_FLAGS="-flto=thin -fuse-ld=lld"

FROM debian:trixie AS builder
ARG CPU_FLAGS
ARG LTO_FLAGS

# Prisma 엔진 저장 경로 고정
ENV PRISMA_PY_BINARY_CACHE_DIR=/opt/prisma_binaries \
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

# 라이브러리 소스 빌드
COPY requirements.txt .
RUN pip install --no-cache-dir --no-binary=orjson,uvloop,pydantic-core,watchfiles,httptools,MarkupSafe,tiktoken,cryptography,rpds-py -r requirements.txt || \
    pip install --no-cache-dir -r requirements.txt

# Prisma 설치 및 엔진 미리 다운로드
RUN npm install -g prisma && \
    mkdir -p ${PRISMA_PY_BINARY_CACHE_DIR}

COPY . .

# Prisma Generate (이 단계에서 엔진이 /opt/prisma_binaries에 담김)
RUN prisma generate --schema=./litellm/proxy/schema.prisma

# Admin UI 및 빌드
RUN sed -i 's/\r$//' docker/build_admin_ui.sh && \
    chmod +x docker/build_admin_ui.sh && \
    ./docker/build_admin_ui.sh && \
    rm -rf dist/* && python3 -m build && \
    pip install dist/*.whl

# ==========================================
# 2. Runtime Stage
# ==========================================
FROM debian:trixie AS runtime

# 중요: 런타임에도 엔진 경로를 동일하게 지정
ENV PRISMA_PY_BINARY_CACHE_DIR=/opt/prisma_binaries \
    DEBIAN_FRONTEND=noninteractive \
    PATH="/opt/venv/bin:$PATH" \
    LD_PRELOAD="/usr/local/lib/libjemalloc.so.2" \
    MALLOC_CONF="background_thread:true,metadata_thp:auto,percpu_arena:percpu,tcache_max:32768,dirty_decay_ms:30000,muzzy_decay_ms:30000" \
    PYTHONOPTIMIZE=2

RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 \
    libsndfile1 \
    libatomic1 \
    nodejs \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# 빌드 결과물 및 'Prisma 엔진' 통째로 이관
COPY --from=builder /usr/local/lib/libjemalloc.so* /usr/local/lib/
COPY --from=builder /opt/venv /opt/venv
COPY --from=builder /opt/prisma_binaries /opt/prisma_binaries
COPY --from=builder /app /app

RUN /sbin/ldconfig && \
    find /opt/venv -type d -path "*/tornado/test" -exec rm -rf {} + || true && \
    chmod +x docker/entrypoint.sh docker/prod_entrypoint.sh

EXPOSE 4000/tcp
ENTRYPOINT ["docker/prod_entrypoint.sh"]
CMD ["--port", "4000"]
