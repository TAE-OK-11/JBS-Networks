ARG NGINX_VERSION=1.29.7
ARG CPU_FLAGS="-O3 -march=znver3 -mtune=znver3 -mavx2 -mfma -mbmi2 -madx -DNDEBUG -fPIC"
ARG LTO_FLAGS="-flto=auto"

FROM debian:trixie-slim AS builder
ARG CPU_FLAGS
ARG LTO_FLAGS
ARG NGINX_VERSION

# AWS-LC 빌드에 필요한 golang과 ninja-build 추가
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential cmake wget curl perl ca-certificates binutils \
    libpcre2-dev pkg-config git golang ninja-build && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /tmp

# ✅ AWS-LC 소스 다운로드 및 정적 빌드 (BoringSSL 호환 구조)
RUN git clone --depth=1 https://github.com/aws/aws-lc.git /tmp/aws-lc && \
    cd /tmp/aws-lc && \
    cmake -B build -GNinja \
        -DCMAKE_BUILD_TYPE=Release \
        -DBUILD_SHARED_LIBS=OFF \
        -DCMAKE_C_FLAGS="${CPU_FLAGS} ${LTO_FLAGS}" \
        -DCMAKE_CXX_FLAGS="${CPU_FLAGS} ${LTO_FLAGS}" && \
    ninja -C build

RUN wget -qO- https://github.com/jemalloc/jemalloc/releases/download/5.3.0/jemalloc-5.3.0.tar.bz2 | tar -xjf - && \
    cd jemalloc-5.3.0 && \
    CFLAGS="${CPU_FLAGS} ${LTO_FLAGS}" CXXFLAGS="${CPU_FLAGS} ${LTO_FLAGS}" LDFLAGS="${LTO_FLAGS}" \
    ./configure --prefix=/usr/local --enable-stats --disable-cxx && \
    make -j$(nproc) && make install

RUN git clone --depth=1 https://github.com/zlib-ng/zlib-ng.git && \
    cd zlib-ng && \
    cmake -B build \
        -DCMAKE_C_FLAGS="${CPU_FLAGS} ${LTO_FLAGS}" \
        -DZLIB_COMPAT=ON \
        -DCMAKE_INSTALL_PREFIX=/usr/local && \
    cmake --build build --config Release -j$(nproc) && \
    cmake --install build

RUN wget -qO- https://github.com/facebook/zstd/releases/download/v1.5.7/zstd-1.5.7.tar.gz | tar -zxf - && \
    cd zstd-1.5.7 && \
    CFLAGS="${CPU_FLAGS} ${LTO_FLAGS}" LDFLAGS="${LTO_FLAGS}" \
    make -j$(nproc) && make install PREFIX=/usr/local

RUN git clone --depth=1 --recurse-submodules https://github.com/google/ngx_brotli.git && \
    cd /tmp/ngx_brotli/deps/brotli && \
    mkdir -p out && \
    cmake -DBUILD_SHARED_LIBS=OFF -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_C_FLAGS="${CPU_FLAGS} ${LTO_FLAGS}" \
        -DCMAKE_CXX_FLAGS="${CPU_FLAGS} ${LTO_FLAGS}" \
        -DCMAKE_INSTALL_PREFIX=/usr/local . && \
    make -j$(nproc) && make install && \
    cd /tmp && \
    git clone --depth=1 https://github.com/HanadaLee/ngx_http_zstd_module.git

RUN curl -fSL "https://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz" | tar -zxf - && \
    mv "nginx-${NGINX_VERSION}" nginx

WORKDIR /tmp/nginx

RUN sed -i 's/-l:libzstd.a/-lzstd/g' /tmp/ngx_http_zstd_module/config

# NGINX 빌드 (AWS-LC 정적 링크, TFO 및 고음질 스트리밍 최적화 유지)
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
    --with-compat \
    --with-http_v2_module \
    --with-http_v3_module \
    --with-http_ssl_module \
    --with-http_realip_module \
    --with-http_stub_status_module \
    --with-http_gzip_static_module \
    --with-http_gunzip_module \
    --with-http_slice_module \
    --with-openssl=/tmp/aws-lc \
    --add-dynamic-module=/tmp/ngx_brotli \
    --add-dynamic-module=/tmp/ngx_http_zstd_module \
    --with-cc-opt="${CPU_FLAGS} ${LTO_FLAGS} -I/usr/local/include" \
    --with-ld-opt="${LTO_FLAGS} -L/usr/local/lib -Wl,-rpath,/usr/local/lib -Wl,--as-needed" && \
    make -j$(nproc) && make install && \
    strip -s /usr/sbin/nginx /usr/lib/nginx/modules/*.so

# ── Runtime stage ──────────────────────────────────────────────────────────────
FROM debian:trixie-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    libpcre2-8-0 ca-certificates libbrotli1 libzstd1 && \
    rm -rf /var/lib/apt/lists/*

COPY --from=builder /usr/sbin/nginx /usr/sbin/nginx
COPY --from=builder /usr/lib/nginx/modules /usr/lib/nginx/modules
COPY --from=builder /etc/nginx /etc/nginx

RUN mkdir -p /etc/nginx/logs && \
    touch /etc/nginx/logs/error.log && \
    chmod -R 755 /etc/nginx/logs

# ✅ AWS-LC는 NGINX 바이너리에 내장되었으므로 libssl/libcrypto 복사가 필요 없음!
# zlib-ng 및 jemalloc 런타임 라이브러리만 복사
COPY --from=builder /usr/local/lib/libz.so* /usr/local/lib/
COPY --from=builder /usr/local/lib/libjemalloc.so.2 /usr/local/lib/libjemalloc.so.2

RUN echo "/usr/local/lib" > /etc/ld.so.conf.d/custom-libs.conf && \
    ldconfig

ENV LD_PRELOAD="/usr/local/lib/libjemalloc.so.2" \
    MALLOC_CONF="background_thread:true,metadata_thp:auto,tcache_max:4096,dirty_decay_ms:1000,muzzy_decay_ms:5000"

LABEL project="JBS Networks 4.3" \
      optimization="Zen3/AWS-LC/QUIC/HTTP3/Zstd/Brotli/Jemalloc/Full-LTO/Slice"

CMD ["nginx", "-g", "daemon off;"]
