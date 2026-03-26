ARG NGINX_VERSION=1.29.7
ARG OPENSSL_VERSION=3.5.4
ARG CPU_FLAGS="-O3 -march=znver3 -mtune=znver3 -mavx2 -mfma -mbmi2 -madx -DNDEBUG -fPIC"
ARG LTO_FLAGS="-flto=auto"

FROM debian:trixie-slim AS builder
ARG CPU_FLAGS
ARG LTO_FLAGS
ARG NGINX_VERSION
ARG OPENSSL_VERSION

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential cmake wget curl perl ca-certificates binutils \
    libpcre2-dev pkg-config git && rm -rf /var/lib/apt/lists/*

WORKDIR /tmp

# OpenSSL 3.5.4 빌드 (동적 링크용)
RUN curl -fSL "https://github.com/openssl/openssl/releases/download/openssl-${OPENSSL_VERSION}/openssl-${OPENSSL_VERSION}.tar.gz" | tar -zxf - && \
    mv "openssl-${OPENSSL_VERSION}" openssl && \
    cd openssl && \
    ./config --prefix=/opt/openssl --libdir=lib \
        enable-tls1_3 enable-quic no-tests \
        ${CPU_FLAGS} ${LTO_FLAGS} && \
    make -j$(nproc) && make install

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

# 주의: --with-openssl 플래그 제거 (동적 링크를 위함), slice 모듈 추가
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
    --add-dynamic-module=/tmp/ngx_brotli \
    --add-dynamic-module=/tmp/ngx_http_zstd_module \
    --with-cc-opt="${CPU_FLAGS} ${LTO_FLAGS} -I/opt/openssl/include -I/usr/local/include" \
    --with-ld-opt="${LTO_FLAGS} -L/opt/openssl/lib -L/usr/local/lib -Wl,-rpath,/opt/openssl/lib -Wl,-rpath,/usr/local/lib -Wl,--as-needed" && \
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

# OpenSSL 3.5 런타임 라이브러리
COPY --from=builder /opt/openssl/lib/libssl.so* /opt/openssl/lib/
COPY --from=builder /opt/openssl/lib/libcrypto.so* /opt/openssl/lib/

# zlib-ng (와일드카드로 실제 파일과 심링크 모두 복사)
COPY --from=builder /usr/local/lib/libz.so* /usr/local/lib/

# jemalloc
COPY --from=builder /usr/local/lib/libjemalloc.so.2 /usr/local/lib/libjemalloc.so.2

RUN echo "/opt/openssl/lib" > /etc/ld.so.conf.d/openssl.conf && \
    echo "/usr/local/lib"   > /etc/ld.so.conf.d/custom-libs.conf && \
    ldconfig

ENV LD_PRELOAD="/usr/local/lib/libjemalloc.so.2" \
    MALLOC_CONF="background_thread:true,metadata_thp:auto,tcache_max:4096,dirty_decay_ms:1000,muzzy_decay_ms:5000"

LABEL project="JBS Networks 4.3" \
      optimization="Zen3/OpenSSL3.5-LTS/QUIC-0RTT/HTTP3/Zstd/Brotli/Jemalloc/Full-LTO/Slice"

CMD ["nginx", "-g", "daemon off;"]
