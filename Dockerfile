# syntax=docker/dockerfile:1
ARG NGINX_VERSION=1.29.0
ARG CPU_FLAGS="-O3 -march=znver3 -mtune=znver3 -mavx2 -mfma -mbmi2 -madx -DNDEBUG -fPIC"
ARG LTO_FLAGS="-flto"

#####################################################
### Stage 1: 모든 부품 소스 빌드 및 조립 (Builder)
FROM debian:trixie-slim AS builder
ARG CPU_FLAGS
ARG LTO_FLAGS
ARG NGINX_VERSION

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential cmake wget curl perl ca-certificates binutils \
    libpcre2-dev pkg-config git && rm -rf /var/lib/apt/lists/*

WORKDIR /tmp

# 1. QuicTLS (OpenSSL for QUIC)
RUN curl -L https://github.com/quictls/openssl/archive/openssl-3.1.5-quic1.tar.gz | tar -zxf - && mv openssl-* quictls

# 2. jemalloc (메모리 최적화)
RUN wget -qO- https://github.com/jemalloc/jemalloc/releases/download/5.3.0/jemalloc-5.3.0.tar.bz2 | tar -xjf - && \
    cd jemalloc-5.3.0 && ./configure --prefix=/usr/local --enable-stats --disable-cxx && make -j$(nproc) && make install

# 3. zlib-ng (압축 가속)
RUN git clone --depth=1 https://github.com/zlib-ng/zlib-ng.git && \
    cd zlib-ng && cmake -B build -DCMAKE_C_FLAGS="${CPU_FLAGS}" -DZLIB_COMPAT=ON -DCMAKE_INSTALL_PREFIX=/usr/local && \
    cmake --build build --config Release -j$(nproc) && cmake --install build

# 4. Zstd (고성능 압축 라이브러리)
RUN wget -qO- https://github.com/facebook/zstd/releases/download/v1.5.6/zstd-1.5.6.tar.gz | tar -zxf - && \
    cd zstd-1.5.6 && CFLAGS="${CPU_FLAGS}" make -j$(nproc) && make install PREFIX=/usr/local

# 5. Brotli & Zstd 모듈 소스 + [Brotli 라이브러리 빌드]
RUN git clone --depth=1 --recurse-submodules https://github.com/google/ngx_brotli.git && \
    cd /tmp/ngx_brotli/deps/brotli && \
    mkdir -p out && \
    cmake -DBUILD_SHARED_LIBS=OFF -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr/local . && \
    make -j$(nproc) && make install && \
    cd /tmp && \
    git clone --depth=1 https://github.com/HanadaLee/ngx_http_zstd_module.git

# 6. Nginx 본체 빌드 (HTTP/3 + RealIP + Zen 3)
RUN curl -fSL "https://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz" | tar -zxf - && mv "nginx-${NGINX_VERSION}" nginx
WORKDIR /tmp/nginx

# Zstd 모듈 링킹 에러 방지 패치
RUN sed -i 's/-l:libzstd.a/-lzstd/g' /tmp/ngx_http_zstd_module/config

RUN ./configure \
    --prefix=/etc/nginx \
    --sbin-path=/usr/sbin/nginx \
    --modules-path=/usr/lib/nginx/modules \
    --conf-path=/etc/nginx/nginx.conf \
    --error-log-path=/etc/nginx/logs/error.log \
    --http-log-path=/etc/nginx/logs/access.log \
    --pid-path=/var/run/nginx.pid \
    --with-pcre-jit \
    --with-threads \
    --with-file-aio \
    --with-http_v2_module \
    --with-http_v3_module \
    --with-http_ssl_module \
    --with-http_realip_module \
    --with-http_stub_status_module \
    --with-http_gzip_static_module \
    --with-openssl=/tmp/quictls \
    --add-dynamic-module=/tmp/ngx_brotli \
    --add-dynamic-module=/tmp/ngx_http_zstd_module \
    --with-cc-opt="${CPU_FLAGS} ${LTO_FLAGS} -I/usr/local/include" \
    --with-ld-opt="${LTO_FLAGS} -L/usr/local/lib -Wl,-rpath,/usr/local/lib -Wl,--as-needed" && \
    make -j$(nproc) && make install && strip -s /usr/sbin/nginx /usr/lib/nginx/modules/*.so

#####################################################
### Stage 2: 최종 런타임 이미지 (Runtime)
FROM debian:trixie-slim
RUN apt-get update && apt-get install -y --no-install-recommends \
    libpcre2-8-0 ca-certificates libbrotli1 libzstd1 && rm -rf /var/lib/apt/lists/*

# 바이너리와 모듈 복사
COPY --from=builder /usr/sbin/nginx /usr/sbin/nginx
COPY --from=builder /usr/lib/nginx/modules /usr/lib/nginx/modules

# 필수 설정 파일(mime.types 등)과 로그 폴더 준비
COPY --from=builder /etc/nginx /etc/nginx
RUN mkdir -p /etc/nginx/logs && touch /etc/nginx/logs/error.log && chmod -R 755 /etc/nginx/logs

# 최적화 라이브러리 복사
COPY --from=builder /usr/local/lib/libjemalloc.so.2 /usr/local/lib/libjemalloc.so.2
COPY --from=builder /usr/local/lib/libz.so.1.* /usr/local/lib/libz-ng.so

# 시스템 라이브러리 경로 업데이트
RUN echo "/usr/local/lib" > /etc/ld.so.conf.d/custom-libs.conf && ldconfig

# [Zen 3 최적화 심장 주입]
ENV LD_PRELOAD="/usr/local/lib/libjemalloc.so.2:/usr/local/lib/libz-ng.so" \
    MALLOC_CONF="background_thread:true,metadata_thp:auto,tcache_max:4096,dirty_decay_ms:1000,muzzy_decay_ms:5000"

LABEL project="JBS Networks 4.0 Ultra" \
      optimization="Zen3/QuicTLS/HTTP3/RealIP/Zstd/Brotli/Jemalloc"

CMD ["nginx", "-g", "daemon off;"]
