# syntax=docker/dockerfile:1.7

ARG NGINX_VERSION=1.29.8
ARG NGINX_SHA256=7f1b985dace8fe706dfc288b83927c928f0ae60bcb7507c2d4e0025eca7280c3
ARG PCRE2_VERSION=10.47
ARG PCRE2_SHA256=c08ae2388ef333e8403e670ad70c0a11f1eed021fd88308d7e02f596fcd9dc16
ARG AWSLC_VERSION=v1.72.0
ARG JEMALLOC_VERSION=5.3.1
ARG JEMALLOC_SHA256=3826bc80232f22ed5c4662f3034f799ca316e819103bdc7bb99018a421706f92
ARG ZLIBNG_VERSION=2.3.3
ARG ZLIBNG_SHA256=f9c65aa9c852eb8255b636fd9f07ce1c406f061ec19a2e7d508b318ca0c907d1
ARG ZSTD_VERSION=1.5.7
ARG ZSTD_SHA256=eb33e51f49a15e023950cd7825ca74a4a2b43db8354825ac24fc1b7ee09e6fa3
ARG NGX_ZSTD_MODULE_VERSION=0.1.1
ARG NGX_BROTLI_REF=master

ARG CPU_FLAGS='-O3 -march=znver3 -mtune=znver3 -pipe -fstack-protector-strong -D_FORTIFY_SOURCE=3 -ffunction-sections -fdata-sections -fno-semantic-interposition -DNDEBUG'
ARG LTO_FLAGS='-flto=full'

FROM debian:trixie-slim AS builder

ARG NGINX_VERSION
ARG NGINX_SHA256
ARG PCRE2_VERSION
ARG PCRE2_SHA256
ARG AWSLC_VERSION
ARG JEMALLOC_VERSION
ARG JEMALLOC_SHA256
ARG ZLIBNG_VERSION
ARG ZLIBNG_SHA256
ARG ZSTD_VERSION
ARG ZSTD_SHA256
ARG NGX_ZSTD_MODULE_VERSION
ARG NGX_BROTLI_REF
ARG CPU_FLAGS
ARG LTO_FLAGS

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ENV DEBIAN_FRONTEND=noninteractive \
    CC=clang \
    CXX=clang++ \
    AR=llvm-ar \
    RANLIB=llvm-ranlib \
    NM=llvm-nm \
    LD=ld.lld

RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    binutils \
    build-essential \
    ca-certificates \
    clang \
    cmake \
    curl \
    git \
    golang \
    lld \
    llvm \
    ninja-build \
    perl \
    pkg-config \
    wget \
    xz-utils \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /tmp

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
      --enable-shared \
      CC="clang" \
      CXX="clang++" \
      AR="llvm-ar" \
      RANLIB="llvm-ranlib" \
      NM="llvm-nm"; \
    make -j"$(nproc)"; \
    make install

RUN set -eux; \
    git clone --branch "${AWSLC_VERSION}" --depth=1 https://github.com/aws/aws-lc.git /tmp/aws-lc; \
    cmake -S /tmp/aws-lc -B /tmp/aws-lc/build -GNinja \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_C_COMPILER=clang \
      -DCMAKE_CXX_COMPILER=clang++ \
      -DCMAKE_LINKER=ld.lld \
      -DCMAKE_AR=llvm-ar \
      -DCMAKE_RANLIB=llvm-ranlib \
      -DCMAKE_NM=llvm-nm \
      -DBUILD_SHARED_LIBS=ON \
      -DBUILD_TESTING=OFF \
      -DCMAKE_INSTALL_PREFIX=/opt/awslc \
      -DCMAKE_INSTALL_LIBDIR=lib \
      -DCMAKE_C_FLAGS="${CPU_FLAGS} -fPIC" \
      -DCMAKE_CXX_FLAGS="${CPU_FLAGS} -fPIC" \
      -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=ON; \
    ninja -C /tmp/aws-lc/build; \
    ninja -C /tmp/aws-lc/build install

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
      --disable-cxx \
      --enable-stats \
      CC="clang" \
      CXX="clang++" \
      AR="llvm-ar" \
      RANLIB="llvm-ranlib" \
      NM="llvm-nm"; \
    make -j"$(nproc)"; \
    make install

RUN set -eux; \
    wget -qO "zlib-ng-${ZLIBNG_VERSION}.tar.gz" \
      "https://github.com/zlib-ng/zlib-ng/archive/refs/tags/${ZLIBNG_VERSION}.tar.gz"; \
    echo "${ZLIBNG_SHA256}  zlib-ng-${ZLIBNG_VERSION}.tar.gz" | sha256sum -c -; \
    tar -xzf "zlib-ng-${ZLIBNG_VERSION}.tar.gz"; \
    cmake -S "/tmp/zlib-ng-${ZLIBNG_VERSION}" -B /tmp/zlib-ng/build -GNinja \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_C_COMPILER=clang \
      -DCMAKE_AR=llvm-ar \
      -DCMAKE_RANLIB=llvm-ranlib \
      -DCMAKE_C_FLAGS="${CPU_FLAGS} ${LTO_FLAGS}" \
      -DCMAKE_SHARED_LINKER_FLAGS="-fuse-ld=lld ${LTO_FLAGS} -Wl,--gc-sections" \
      -DCMAKE_EXE_LINKER_FLAGS="-fuse-ld=lld ${LTO_FLAGS} -Wl,--gc-sections" \
      -DZLIB_COMPAT=ON \
      -DCMAKE_INSTALL_PREFIX=/usr/local; \
    cmake --build /tmp/zlib-ng/build --parallel; \
    cmake --install /tmp/zlib-ng/build

RUN set -eux; \
    wget -qO "zstd-${ZSTD_VERSION}.tar.gz" \
      "https://github.com/facebook/zstd/releases/download/v${ZSTD_VERSION}/zstd-${ZSTD_VERSION}.tar.gz"; \
    echo "${ZSTD_SHA256}  zstd-${ZSTD_VERSION}.tar.gz" | sha256sum -c -; \
    tar -xzf "zstd-${ZSTD_VERSION}.tar.gz"; \
    cd "zstd-${ZSTD_VERSION}"; \
    CFLAGS="${CPU_FLAGS} ${LTO_FLAGS}" \
    LDFLAGS="-fuse-ld=lld ${LTO_FLAGS} -Wl,--gc-sections" \
    make -j"$(nproc)"; \
    make install PREFIX=/usr/local

# ✅ 수정됨: Brotli 빌드 시 --target brotlienc 제거
RUN set -eux; \
    git clone --branch "${NGX_BROTLI_REF}" --depth=1 --recurse-submodules -j8 \
      https://github.com/google/ngx_brotli.git /tmp/ngx_brotli; \
    cmake -S /tmp/ngx_brotli/deps/brotli -B /tmp/ngx_brotli/deps/brotli/out -GNinja \
      -DCMAKE_BUILD_TYPE=Release \
      -DBUILD_SHARED_LIBS=ON \
      -DCMAKE_C_COMPILER=clang \
      -DCMAKE_CXX_COMPILER=clang++ \
      -DCMAKE_AR=llvm-ar \
      -DCMAKE_RANLIB=llvm-ranlib \
      -DCMAKE_C_FLAGS="${CPU_FLAGS} ${LTO_FLAGS}" \
      -DCMAKE_CXX_FLAGS="${CPU_FLAGS} ${LTO_FLAGS}" \
      -DCMAKE_INSTALL_PREFIX=/usr/local; \
    cmake --build /tmp/ngx_brotli/deps/brotli/out --parallel; \
    cmake --install /tmp/ngx_brotli/deps/brotli/out

RUN git clone --branch "${NGX_ZSTD_MODULE_VERSION}" --depth=1 \
      https://github.com/HanadaLee/ngx_http_zstd_module.git /tmp/ngx_http_zstd_module

RUN set -eux; \
    curl -fSL "https://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz" -o "nginx-${NGINX_VERSION}.tar.gz"; \
    echo "${NGINX_SHA256}  nginx-${NGINX_VERSION}.tar.gz" | sha256sum -c -; \
    tar -xzf "nginx-${NGINX_VERSION}.tar.gz"; \
    mv "nginx-${NGINX_VERSION}" /tmp/nginx

WORKDIR /tmp/nginx

RUN sed -i 's/-l:libzstd.a/-lzstd/g' /tmp/ngx_http_zstd_module/config

RUN set -eux; \
    export PKG_CONFIG_PATH=/usr/local/lib/pkgconfig; \
    ./configure \
      --prefix=/etc/nginx \
      --sbin-path=/usr/sbin/nginx \
      --modules-path=/usr/lib/nginx/modules \
      --conf-path=/etc/nginx/nginx.conf \
      --error-log-path=/var/log/nginx/error.log \
      --http-log-path=/var/log/nginx/access.log \
      --pid-path=/var/run/nginx.pid \
      --lock-path=/var/run/nginx.lock \
      --http-client-body-temp-path=/var/cache/nginx/client_temp \
      --http-proxy-temp-path=/var/cache/nginx/proxy_temp \
      --http-fastcgi-temp-path=/var/cache/nginx/fastcgi_temp \
      --http-uwsgi-temp-path=/var/cache/nginx/uwsgi_temp \
      --http-scgi-temp-path=/var/cache/nginx/scgi_temp \
      --user=nginx --group=nginx \
      --with-cc=clang \
      --with-pcre-jit \
      --with-threads \
      --with-file-aio \
      --with-http_ssl_module \
      --with-http_v2_module \
      --with-http_v3_module \
      --with-http_realip_module \
      --with-http_stub_status_module \
      --with-http_gzip_static_module \
      --with-http_gunzip_module \
      --with-http_slice_module \
      --with-http_auth_request_module \
      --with-http_sub_module \
      --with-http_secure_link_module \
      --with-stream \
      --with-stream_ssl_module \
      --with-stream_realip_module \
      --with-stream_ssl_preread_module \
      --add-module=/tmp/ngx_brotli \
      --add-module=/tmp/ngx_http_zstd_module \
      --with-cc-opt="${CPU_FLAGS} ${LTO_FLAGS} -I/opt/awslc/include -I/usr/local/include" \
      --with-ld-opt="-fuse-ld=lld ${LTO_FLAGS} -Wl,-O3 -Wl,--as-needed -Wl,--gc-sections -Wl,-rpath,/opt/awslc/lib:/usr/local/lib -L/opt/awslc/lib -L/usr/local/lib -lssl -lcrypto -lpcre2-8 -lz -lzstd -lbrotlienc -lbrotlicommon"; \
    make -j"$(nproc)"; \
    make install; \
    strip -s /usr/sbin/nginx; \
    ldd /usr/sbin/nginx | tee /tmp/nginx.ldd.txt; \
    ! grep -q 'not found' /tmp/nginx.ldd.txt

FROM debian:trixie-slim AS runtime

SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN groupadd -r nginx && useradd -r -g nginx -s /usr/sbin/nologin nginx

COPY --from=builder /usr/sbin/nginx /usr/sbin/nginx
COPY --from=builder /etc/nginx /etc/nginx
COPY --from=builder /usr/local/lib/libpcre2-8.so* /usr/local/lib/
COPY --from=builder /usr/local/lib/libz.so* /usr/local/lib/
COPY --from=builder /usr/local/lib/libjemalloc.so* /usr/local/lib/
COPY --from=builder /usr/local/lib/libzstd.so* /usr/local/lib/
COPY --from=builder /usr/local/lib/libbrotli*.so* /usr/local/lib/
COPY --from=builder /opt/awslc/lib/libssl.so* /opt/awslc/lib/
COPY --from=builder /opt/awslc/lib/libcrypto.so* /opt/awslc/lib/

RUN set -eux; \
    mkdir -p /var/log/nginx /var/cache/nginx /run; \
    chown -R nginx:nginx /etc/nginx /var/log/nginx /var/cache/nginx; \
    ln -sf /dev/stdout /var/log/nginx/access.log; \
    ln -sf /dev/stderr /var/log/nginx/error.log; \
    printf '/usr/local/lib\n/opt/awslc/lib\n' > /etc/ld.so.conf.d/custom-nginx.conf; \
    ldconfig; \
    nginx -t

ENV LD_PRELOAD=/usr/local/lib/libjemalloc.so.2 \
    MALLOC_CONF=background_thread:true,metadata_thp:auto,percpu_arena:percpu,tcache_max:32768,tcache_ncached_max:256,experimental_tcache_gc:true,disable_large_size_classes:true,calloc_madvise_threshold:131072,process_madvise_max_batch:64,dirty_decay_ms:30000,muzzy_decay_ms:30000,stats_print:false

EXPOSE 80 443/tcp 443/udp
STOPSIGNAL SIGQUIT

LABEL project="JBS Networks 4.3" \
      optimization="Extreme/Znver3/Full-LTO/Clang/LLD/AWS-LC/Jemalloc/zlib-ng/Brotli/Zstd"

CMD ["nginx", "-g", "daemon off;"]
