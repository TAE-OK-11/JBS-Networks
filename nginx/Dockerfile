# syntax=docker/dockerfile:1.7

ARG NGINX_VERSION=1.29.8
ARG NGINX_SHA256=7f1b985dace8fe706dfc288b83927c928f0ae60bcb7507c2d4e0025eca7280c3

ARG PCRE2_VERSION=10.47
ARG PCRE2_SHA256=c08ae2388ef333e8403e670ad70c0a11f1eed021fd88308d7e02f596fcd9dc16

ARG AWSLC_VERSION=v1.72.0

ARG JEMALLOC_VERSION=5.3.1
ARG JEMALLOC_SHA256=3826bc80232f22ed5c4662f3034f799ca316e819103bdc7bb99018a421706f92

ARG ZLIBRS_VERSION=v0.6.3
ARG CARGOC_VERSION=v0.10.7

ARG ZSTD_VERSION=1.5.7

ARG CPU_FLAGS="-O3 -march=znver3 -mtune=znver3 -pipe -fstack-protector-strong -D_FORTIFY_SOURCE=3 -ffunction-sections -fdata-sections -fno-semantic-interposition -DNDEBUG"
ARG LTO_FLAGS="-flto=full"

FROM debian:trixie-slim AS builder
ARG NGINX_VERSION
ARG NGINX_SHA256
ARG PCRE2_VERSION
ARG PCRE2_SHA256
ARG AWSLC_VERSION
ARG JEMALLOC_VERSION
ARG JEMALLOC_SHA256
ARG ZLIBRS_VERSION
ARG CARGOC_VERSION
ARG ZSTD_VERSION
ARG CPU_FLAGS
ARG LTO_FLAGS

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    bzip2 \
    ca-certificates \
    cargo \
    clang \
    cmake \
    curl \
    git \
    golang \
    lld \
    llvm \
    ninja-build \
    patchelf \
    perl \
    pkg-config \
    rustc \
    wget \
    xz-utils \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /tmp

# PCRE2
RUN set -eux; \
    wget -qO "pcre2-${PCRE2_VERSION}.tar.gz" \
      "https://github.com/PCRE2Project/pcre2/releases/download/pcre2-${PCRE2_VERSION}/pcre2-${PCRE2_VERSION}.tar.gz"; \
    echo "${PCRE2_SHA256}  pcre2-${PCRE2_VERSION}.tar.gz" | sha256sum -c -; \
    tar -xzf "pcre2-${PCRE2_VERSION}.tar.gz"; \
    cd "pcre2-${PCRE2_VERSION}"; \
    CFLAGS="${CPU_FLAGS} ${LTO_FLAGS}" \
    LDFLAGS="-fuse-ld=lld ${LTO_FLAGS} -Wl,--gc-sections" \
    ./configure \
      --prefix=/usr/local \
      --enable-jit \
      --enable-shared; \
    make -j"$(nproc)"; \
    make install; \
    strip -s /usr/local/lib/libpcre2-8.so* || true

# AWS-LC
RUN set -eux; \
    git clone --branch "${AWSLC_VERSION}" --depth=1 https://github.com/aws/aws-lc.git /tmp/aws-lc; \
    cmake -S /tmp/aws-lc -B /tmp/aws-lc/build -GNinja \
      -DCMAKE_BUILD_TYPE=Release \
      -DBUILD_SHARED_LIBS=ON \
      -DBUILD_TESTING=OFF \
      -DCMAKE_INSTALL_PREFIX=/opt/awslc \
      -DCMAKE_INSTALL_LIBDIR=lib \
      -DCMAKE_C_COMPILER=clang \
      -DCMAKE_CXX_COMPILER=clang++ \
      -DCMAKE_C_FLAGS="${CPU_FLAGS} ${LTO_FLAGS} -fPIC" \
      -DCMAKE_CXX_FLAGS="${CPU_FLAGS} ${LTO_FLAGS} -fPIC" \
      -DCMAKE_SHARED_LINKER_FLAGS="-fuse-ld=lld ${LTO_FLAGS} -Wl,--gc-sections" \
      -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=ON; \
    ninja -C /tmp/aws-lc/build install; \
    strip -s /opt/awslc/lib/libssl.so* /opt/awslc/lib/libcrypto.so* || true

# jemalloc
RUN set -eux; \
    wget -qO "jemalloc-${JEMALLOC_VERSION}.tar.bz2" \
      "https://github.com/jemalloc/jemalloc/releases/download/${JEMALLOC_VERSION}/jemalloc-${JEMALLOC_VERSION}.tar.bz2"; \
    echo "${JEMALLOC_SHA256}  jemalloc-${JEMALLOC_VERSION}.tar.bz2" | sha256sum -c -; \
    tar -xjf "jemalloc-${JEMALLOC_VERSION}.tar.bz2"; \
    cd "jemalloc-${JEMALLOC_VERSION}"; \
    CFLAGS="${CPU_FLAGS} ${LTO_FLAGS}" \
    LDFLAGS="-fuse-ld=lld ${LTO_FLAGS} -Wl,--gc-sections" \
    ./configure \
      --prefix=/usr/local \
      --disable-cxx; \
    make -j"$(nproc)"; \
    make install; \
    strip -s /usr/local/lib/libjemalloc.so* || true

# zlib-rs  ✅ self-copy 버그 수정판
RUN set -eux; \
    git clone --branch "${ZLIBRS_VERSION}" --depth=1 https://github.com/trifectatechfoundation/zlib-rs.git /tmp/zlib-rs; \
    curl -fsSL "https://github.com/lu-zero/cargo-c/releases/download/${CARGOC_VERSION}/cargo-c-x86_64-unknown-linux-musl.tar.gz" \
      -o /tmp/cargo-c.tar.gz; \
    mkdir -p /tmp/cargo-c-tmp; \
    tar -xzf /tmp/cargo-c.tar.gz -C /tmp/cargo-c-tmp; \
    CARGO_CBUILD="$(find /tmp/cargo-c-tmp -type f -name cargo-cbuild | head -n1)"; \
    CARGO_CINSTALL="$(find /tmp/cargo-c-tmp -type f -name cargo-cinstall | head -n1)"; \
    test -n "${CARGO_CBUILD}"; \
    test -n "${CARGO_CINSTALL}"; \
    install -Dm755 "${CARGO_CBUILD}" /usr/local/bin/cargo-cbuild; \
    install -Dm755 "${CARGO_CINSTALL}" /usr/local/bin/cargo-cinstall; \
    rm -rf /tmp/cargo-c.tar.gz /tmp/cargo-c-tmp; \
    cd /tmp/zlib-rs/libz-rs-sys-cdylib; \
    export RUSTFLAGS="-C target-cpu=znver3 -C opt-level=3 -C codegen-units=1 -C llvm-args=-enable-dfa-jump-thread"; \
    cargo cinstall --release --prefix=/usr/local --libdir=/usr/local/lib; \
    if [ -d /usr/local/include/libz_rs ]; then \
      cp /usr/local/include/libz_rs/zlib.h /usr/local/include/zlib.h; \
      cp /usr/local/include/libz_rs/zconf.h /usr/local/include/zconf.h || true; \
    fi; \
    test -f /usr/local/lib/pkgconfig/libz_rs.pc; \
    test -f /usr/local/lib/libz_rs.so; \
    patchelf --set-soname libz.so.1 /usr/local/lib/libz_rs.so; \
    ln -sf libz_rs.so /usr/local/lib/libz.so.1; \
    ln -sf libz_rs.so /usr/local/lib/libz.so; \
    strip --strip-debug /usr/local/lib/libz_rs.so || true

# zstd
RUN set -eux; \
    wget -qO "zstd-${ZSTD_VERSION}.tar.gz" \
      "https://github.com/facebook/zstd/releases/download/v${ZSTD_VERSION}/zstd-${ZSTD_VERSION}.tar.gz"; \
    tar -xzf "zstd-${ZSTD_VERSION}.tar.gz"; \
    cd "zstd-${ZSTD_VERSION}/build/cmake"; \
    cmake -S . -B build -GNinja \
      -DCMAKE_BUILD_TYPE=Release \
      -DZSTD_BUILD_PROGRAMS=OFF \
      -DZSTD_BUILD_SHARED=ON \
      -DZSTD_BUILD_STATIC=ON \
      -DCMAKE_INSTALL_PREFIX=/usr/local \
      -DCMAKE_C_COMPILER=clang \
      -DCMAKE_C_FLAGS="${CPU_FLAGS} ${LTO_FLAGS} -fPIC" \
      -DCMAKE_SHARED_LINKER_FLAGS="-fuse-ld=lld ${LTO_FLAGS} -Wl,--gc-sections"; \
    ninja -C build install; \
    strip -s /usr/local/lib/libzstd.so* || true

# ngx_brotli + zstd module
RUN set -eux; \
    git clone --recurse-submodules --depth=1 https://github.com/google/ngx_brotli.git /tmp/ngx_brotli; \
    cd /tmp/ngx_brotli/deps/brotli; \
    mkdir -p out; \
    cd out; \
    cmake -G Ninja \
      -DCMAKE_BUILD_TYPE=Release \
      -DBUILD_SHARED_LIBS=OFF \
      -DCMAKE_C_COMPILER=clang \
      -DCMAKE_CXX_COMPILER=clang++ \
      -DCMAKE_C_FLAGS="${CPU_FLAGS} ${LTO_FLAGS} -fPIC" \
      -DCMAKE_CXX_FLAGS="${CPU_FLAGS} ${LTO_FLAGS} -fPIC" \
      ..; \
    ninja; \
    git clone --depth=1 https://github.com/tokers/zstd-nginx-module.git /tmp/zstd-nginx-module

# nginx
RUN set -eux; \
    wget -qO "nginx-${NGINX_VERSION}.tar.gz" "https://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz"; \
    echo "${NGINX_SHA256}  nginx-${NGINX_VERSION}.tar.gz" | sha256sum -c -; \
    tar -xzf "nginx-${NGINX_VERSION}.tar.gz"; \
    cd "nginx-${NGINX_VERSION}"; \
    export PKG_CONFIG_PATH="/opt/awslc/lib/pkgconfig:/usr/local/lib/pkgconfig"; \
    export LD_LIBRARY_PATH="/opt/awslc/lib:/usr/local/lib"; \
    ./configure \
      --prefix=/etc/nginx \
      --sbin-path=/usr/sbin/nginx \
      --modules-path=/usr/lib/nginx/modules \
      --conf-path=/etc/nginx/nginx.conf \
      --error-log-path=/var/log/nginx/error.log \
      --http-log-path=/var/log/nginx/access.log \
      --pid-path=/var/run/nginx.pid \
      --lock-path=/var/run/nginx.lock \
      --user=nginx \
      --group=nginx \
      --with-cc=clang \
      --with-cc-opt="${CPU_FLAGS} ${LTO_FLAGS} -I/opt/awslc/include -I/usr/local/include" \
      --with-ld-opt="-fuse-ld=lld ${LTO_FLAGS} -Wl,--gc-sections -L/opt/awslc/lib -L/usr/local/lib -Wl,-rpath,/opt/awslc/lib:/usr/local/lib -ljemalloc" \
      --with-pcre-jit \
      --with-threads \
      --with-file-aio \
      --with-compat \
      --with-http_ssl_module \
      --with-http_v2_module \
      --with-http_v3_module \
      --with-http_realip_module \
      --with-http_stub_status_module \
      --with-http_sub_module \
      --with-http_slice_module \
      --with-http_gzip_static_module \
      --with-stream \
      --with-stream_ssl_module \
      --with-stream_realip_module \
      --with-stream_ssl_preread_module \
      --add-module=/tmp/ngx_brotli \
      --add-module=/tmp/zstd-nginx-module; \
    make -j"$(nproc)"; \
    make install; \
    strip -s /usr/sbin/nginx || true

FROM debian:trixie-slim AS runtime
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    && rm -rf /var/lib/apt/lists/*

RUN groupadd -r nginx && useradd -r -g nginx -s /usr/sbin/nologin nginx

RUN install -d -o nginx -g nginx \
    /var/cache/nginx \
    /var/log/nginx \
    /var/lib/nginx/body \
    /var/lib/nginx/proxy \
    /var/lib/nginx/fastcgi \
    /var/lib/nginx/uwsgi \
    /var/lib/nginx/scgi \
    /etc/nginx/conf.d \
    /usr/lib/nginx/modules

COPY --from=builder /usr/sbin/nginx /usr/sbin/nginx
COPY --from=builder /etc/nginx /etc/nginx

COPY --from=builder /opt/awslc/lib/libssl.so /opt/awslc/lib/libssl.so
COPY --from=builder /opt/awslc/lib/libcrypto.so /opt/awslc/lib/libcrypto.so

COPY --from=builder /usr/local/lib/libjemalloc.so.2 /usr/local/lib/libjemalloc.so.2
COPY --from=builder /usr/local/lib/libpcre2-8.so.0.15.0 /usr/local/lib/libpcre2-8.so.0.15.0
COPY --from=builder /usr/local/lib/libz_rs.so /usr/local/lib/libz_rs.so
COPY --from=builder /usr/local/lib/libzstd.so /usr/local/lib/libzstd.so
COPY --from=builder /usr/local/lib/libzstd.so.1 /usr/local/lib/libzstd.so.1
COPY --from=builder /usr/local/lib/libzstd.so.1.5.7 /usr/local/lib/libzstd.so.1.5.7

RUN ln -sf /usr/local/lib/libjemalloc.so.2 /usr/local/lib/libjemalloc.so \
    && ln -sf /usr/local/lib/libpcre2-8.so.0.15.0 /usr/local/lib/libpcre2-8.so.0 \
    && ln -sf /usr/local/lib/libpcre2-8.so.0.15.0 /usr/local/lib/libpcre2-8.so \
    && ln -sf /usr/local/lib/libz_rs.so /usr/local/lib/libz.so.1 \
    && ln -sf /usr/local/lib/libz_rs.so /usr/local/lib/libz.so \
    && printf '%s\n%s\n' '/opt/awslc/lib' '/usr/local/lib' > /etc/ld.so.conf.d/jbs-nginx.conf \
    && ldconfig

ENV LD_PRELOAD=/usr/local/lib/libjemalloc.so.2

EXPOSE 80/tcp 443/tcp 443/udp
STOPSIGNAL SIGQUIT

CMD ["nginx", "-g", "daemon off;"]
