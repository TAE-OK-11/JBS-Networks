FROM debian:trixie-slim AS builder

ENV DEBIAN_FRONTEND=noninteractive
ENV CFLAGS="-O3 -march=znver3 -mtune=znver3 -mavx2 -mfma -mbmi2 -madx -flto=auto -fPIC -DNDEBUG -I/usr/local/include"
ENV LDFLAGS="-flto=auto -L/usr/local/lib -Wl,-rpath,/usr/local/lib -Wl,--as-needed"

RUN apt-get update && apt-get install -y \
    build-essential cmake git wget libpcre2-dev \
    libjemalloc-dev golang perl zlib1g-dev

WORKDIR /build

RUN git clone --depth=1 -b openssl-3.1.5+quic https://github.com/quictls/openssl.git quictls && \
    cd quictls && \
    ./config --prefix=/tmp/quictls --libdir=lib enable-tls1_3 && \
    make -j$(nproc) && make install

RUN git clone --depth=1 https://github.com/google/ngx_brotli.git && \
    cd ngx_brotli && git submodule update --init

RUN git clone --depth=1 https://github.com/tokers/zstd-nginx-module.git

RUN git clone --depth=1 https://github.com/zlib-ng/zlib-ng.git && \
    cd zlib-ng && \
    ./configure --zlib-compat && \
    make -j$(nproc) && make install

RUN wget https://nginx.org/download/nginx-1.29.0.tar.gz && \
    tar -zxf nginx-1.29.0.tar.gz

WORKDIR /build/nginx-1.29.0

RUN ./configure \
    --prefix=/etc/nginx \
    --sbin-path=/usr/sbin/nginx \
    --modules-path=/usr/lib/nginx/modules \
    --conf-path=/etc/nginx/nginx.conf \
    --with-http_v2_module \
    --with-http_v3_module \
    --with-http_ssl_module \
    --with-http_realip_module \
    --with-pcre-jit \
    --with-threads \
    --with-file-aio \
    --with-openssl=/build/quictls \
    --add-dynamic-module=/build/ngx_brotli \
    --add-dynamic-module=/build/zstd-nginx-module \
    --with-cc-opt="${CFLAGS}" \
    --with-ld-opt="${LDFLAGS}" && \
    make -j$(nproc) && \
    make install

RUN strip -s /usr/sbin/nginx && \
    strip -s /usr/lib/nginx/modules/*.so

FROM debian:trixie-slim

ENV LD_PRELOAD="/usr/lib/x86_64-linux-gnu/libjemalloc.so.2"

RUN apt-get update && apt-get install -y \
    libjemalloc2 libpcre2-8-0 zlib1g && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

COPY --from=builder /usr/sbin/nginx /usr/sbin/nginx
COPY --from=builder /usr/lib/nginx/modules /usr/lib/nginx/modules
COPY --from=builder /etc/nginx /etc/nginx
COPY --from=builder /usr/local/lib /usr/local/lib

RUN mkdir -p /var/cache/nginx/navidrome /var/log/nginx

EXPOSE 80 443 443/udp

CMD ["nginx", "-g", "daemon off;"]
