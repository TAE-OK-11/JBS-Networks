# ==========================================
# 1. Builder Stage (Now)
# ==========================================
# Zen3 전용 최적화 플래그 및 Thin LTO 적용 (GitHub Actions 메모리 한계 고려)
ARG CPU_FLAGS="-O3 -march=znver3 -mtune=znver3 -mavx2 -mfma -mbmi2 -madx -fPIC -fstack-protector-strong -D_FORTIFY_SOURCE=2 -pipe"
ARG LTO_FLAGS="-flto=thin -fuse-ld=lld"

FROM debian:trixie-slim AS builder
ARG CPU_FLAGS
ARG LTO_FLAGS

ENV DEBIAN_FRONTEND=noninteractive \
    CC="clang" \
    CXX="clang++" \
    CFLAGS="${CPU_FLAGS} ${LTO_FLAGS}" \
    CXXFLAGS="${CPU_FLAGS} ${LTO_FLAGS}" \
    LDFLAGS="${LTO_FLAGS} -Wl,--as-needed -Wl,-O1 -Wl,--sort-common" \
    PATH="/opt/venv/bin:$PATH" \
    # Rust 컴파일 최적화 (Zen3 타겟팅 및 LLVM 링커 지정)
    RUSTFLAGS="-C target-cpu=znver3 -C opt-level=3 -C linker=clang -C link-arg=-fuse-ld=lld -C lto=thin" \
    # Go 컴파일 최적화
    GOAMD64=v3

# 빌드 필수 도구 설치 (LLVM/Clang 및 Rust/Go 툴체인 포함)
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential cmake wget curl git pkg-config \
    python3 python3-pip python3-venv python3-dev \
    nodejs npm rustc cargo golang-go \
    libssl-dev llvm clang lld \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /tmp

# Jemalloc 컴파일 (성능 극대화를 위해 --enable-prof 제거)
RUN wget -qO- https://github.com/jemalloc/jemalloc/releases/download/5.3.0/jemalloc-5.3.0.tar.bz2 | tar -xjf - && \
    cd jemalloc-5.3.0 && \
    ./configure --prefix=/usr/local --disable-cxx --enable-stats && \
    make -j$(nproc) && make install

WORKDIR /app

# 가상환경 선구성
RUN python3 -m venv /opt/venv && \
    pip install --no-cache-dir --upgrade pip build wheel setuptools

# 고성능 Rust/C 기반 라이브러리 강제 교체 및 소스 빌드
# orjson: JSON 파싱
# uvloop: 비동기 이벤트 루프
# pydantic-core: 데이터 검증
# watchfiles: 파일 감시
COPY requirements.txt .
RUN pip install --no-cache-dir --no-binary=orjson,uvloop,pydantic-core,watchfiles,httptools,MarkupSafe -r requirements.txt || \
    pip install --no-cache-dir -r requirements.txt

# Prisma 설치
RUN npm install -g prisma

# 나머지 소스 복사
COPY . .

# Admin UI 빌드 및 패키징
RUN sed -i 's/\r$//' docker/build_admin_ui.sh && \
    chmod +x docker/build_admin_ui.sh && \
    ./docker/build_admin_ui.sh && \
    rm -rf dist/* && python3 -m build && \
    pip install dist/*.whl

# Prisma Generate (데이터베이스 ORM)
RUN prisma generate --schema=./litellm/proxy/schema.prisma

# ==========================================
# 2. Runtime Stage
# ==========================================
FROM debian:trixie-slim AS runtime

ENV DEBIAN_FRONTEND=noninteractive \
    PATH="/opt/venv/bin:$PATH" \
    # Jemalloc 런타임 튜닝 (Zen3 병렬 처리 극대화)
    LD_PRELOAD="/usr/local/lib/libjemalloc.so.2" \
    MALLOC_CONF="background_thread:true,metadata_thp:auto,percpu_arena:percpu,tcache_max:32768,dirty_decay_ms:30000,muzzy_decay_ms:30000,stats_print:false" \
    # Python 런타임 최적화 (docstring 및 assert 제거로 로드 속도 향상)
    PYTHONOPTIMIZE=2 \
    PYTHONNODEBUGRW=1

RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 \
    libsndfile1 \
    nodejs \
    supervisor \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# 빌드 결과물 이관
COPY --from=builder /usr/local/lib/libjemalloc.so* /usr/local/lib/
COPY --from=builder /opt/venv /opt/venv
COPY --from=builder /app /app

# 동적 라이브러리 캐시 갱신 및 테스트 파일 정리
RUN ldconfig && \
    find /opt/venv -type f -path "*/tornado/test/*" -delete && \
    find /opt/venv -type d -path "*/tornado/test" -delete && \
    chmod +x docker/entrypoint.sh docker/prod_entrypoint.sh

EXPOSE 4000/tcp
STOPSIGNAL SIGQUIT

LABEL project="JBS Networks 4.3 - Extreme Performance" \
      optimization="Zen3/Clang/Rust-Core/LTO-Thin/Jemalloc"

ENTRYPOINT ["docker/prod_entrypoint.sh"]
CMD ["--port", "4000"]
