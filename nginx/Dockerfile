# syntax=docker/dockerfile:1.7

# =========================================================
# JBS Networks NGINX 5.2 Resource-Aware Final
# NGINX 1.31.1 Mainline / Network-Optimized Build
# AMD EPYC Zen3 Dedicated Edition
#
# Core:
#   NGINX 1.31.1 Mainline
#   AWS-LC v5.0.0
#   PCRE2 10.47
#   jemalloc 5.3.1
#   zlib-rs 0.6.3
#   cargo-c 0.10.22
#   zstd 1.5.7
#
# Runtime:
#   - rootful container
#   - nginx master runs as root
#   - nginx workers drop to nginx user through nginx.conf
#   - no setcap
#   - no global fixed LD_PRELOAD
#   - jemalloc is enabled only after runtime preload test
#   - worker_processes auto-tuned from cgroup CPU quota
#   - no curl healthcheck
#   - no runtime bash dependency
#   - no runtime useradd/groupadd
#
# Optimization:
#   - Znver3 only
#   - Clang / LLD / Full LTO
#   - AWS-LC IPO/LTO
#   - zlib-rs fat LTO
#   - Brotli IPO/LTO
#   - zstd
#   - PCRE2 JIT
#   - HTTP/2 + HTTP/3 QUIC
#   - reverse proxy oriented module trim
# =========================================================

ARG DEBIAN_TRIXIE_DIGEST="sha256:cedb1ef40439206b673ee8b33a46a03a0c9fa90bf3732f54704f99cb061d2c5a"

ARG NGINX_VERSION=1.31.1
ARG NGINX_SHA256=9fcaaeb8f22544b09a19a761f3412c4112215422401634bebdd1296a403cc4bc

ARG PCRE2_VERSION=10.47
ARG PCRE2_SHA256=c08ae2388ef333e8403e670ad70c0a11f1eed021fd88308d7e02f596fcd9dc16

ARG AWSLC_VERSION=v5.0.0

ARG JEMALLOC_VERSION=5.3.1
ARG JEMALLOC_SHA256=3826bc80232f22ed5c4662f3034f799ca316e819103bdc7bb99018a421706f92

ARG ZLIBRS_VERSION=v0.6.3
ARG CARGOC_VERSION=v0.10.22

ARG ZSTD_VERSION=1.5.7
ARG ZSTD_SHA256=eb33e51f49a15e023950cd7825ca74a4a2b43db8354825ac24fc1b7ee09e6fa3

ARG NGX_ZSTD_MODULE_VERSION=0.1.1
ARG NGX_BROTLI_REF=a71f9312c2deb28875acc7bacfdd5695a111aa53

ARG JBS_NGINX_WORKER_PROCESSES=auto
ARG JBS_NGINX_WORKER_PROCESSES_MAX=8
ARG JBS_USE_JEMALLOC=true

ARG CPU_FLAGS="-O3 -march=znver3 -mtune=znver3 -pipe -fstack-protector-strong -D_FORTIFY_SOURCE=3 -ffunction-sections -fdata-sections -fno-semantic-interposition -fno-plt -fomit-frame-pointer -DNDEBUG"
ARG LTO_FLAGS="-flto=full"

# =========================================================
# Builder
# =========================================================

FROM debian:trixie-slim@${DEBIAN_TRIXIE_DIGEST} AS builder

ARG TARGETARCH
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
    CARGO_NET_GIT_FETCH_WITH_CLI=true

RUN case "${TARGETARCH:-amd64}" in \
      amd64|"") echo "Building for amd64 / znver3";; \
      *) echo "Unsupported TARGETARCH=${TARGETARCH}. This image is x86_64/znver3 only." >&2; exit 1;; \
    esac

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
      autoconf \
      automake \
      binutils \
      build-essential \
      bzip2 \
      ca-certificates \
      cargo \
      clang \
      cmake \
      curl \
      file \
      git \
      golang \
      lld \
      llvm \
      make \
      ninja-build \
      patchelf \
      perl \
      pkg-config \
      rustc \
      wget \
      xz-utils; \
    rm -rf \
      /var/lib/apt/lists/* \
      /usr/share/doc \
      /usr/share/man \
      /usr/share/info \
      /usr/share/lintian \
      /usr/share/linda

WORKDIR /tmp

# ---------------------------------------------------------
# 1) PCRE2
# ---------------------------------------------------------

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
      --disable-static \
      --disable-pcre2-16 \
      --disable-pcre2-32; \
    make -j"$(nproc)"; \
    make install; \
    strip -s /usr/local/lib/libpcre2-8.so* || true; \
    /usr/local/bin/pcre2-config --version

# ---------------------------------------------------------
# 2) AWS-LC
# ---------------------------------------------------------

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
      -DCMAKE_ASM_COMPILER=clang \
      -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=ON \
      -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
      -DCMAKE_C_FLAGS="${CPU_FLAGS} ${LTO_FLAGS} -fPIC" \
      -DCMAKE_CXX_FLAGS="${CPU_FLAGS} ${LTO_FLAGS} -fPIC" \
      -DCMAKE_EXE_LINKER_FLAGS="-fuse-ld=lld ${LTO_FLAGS} -Wl,--gc-sections" \
      -DCMAKE_SHARED_LINKER_FLAGS="-fuse-ld=lld ${LTO_FLAGS} -Wl,--gc-sections"; \
    ninja -C /tmp/aws-lc/build install; \
    strip -s /opt/awslc/lib/libssl.so* /opt/awslc/lib/libcrypto.so* || true; \
    \
    test -f /opt/awslc/lib/libssl.so; \
    test -f /opt/awslc/lib/libcrypto.so; \
    \
    printf '%s\n' \
      '#include <openssl/ssl.h>' \
      'int main(void) {' \
      '    const SSL_METHOD *method = TLS_method();' \
      '    SSL_CTX *ctx = SSL_CTX_new(method);' \
      '    if (ctx == 0) return 1;' \
      '    SSL_CTX_free(ctx);' \
      '    return 0;' \
      '}' \
      > /tmp/awslc_preflight.c; \
    clang -I/opt/awslc/include -L/opt/awslc/lib -fuse-ld=lld \
      -Wl,-rpath,/opt/awslc/lib \
      -o /tmp/awslc_preflight /tmp/awslc_preflight.c \
      -lssl -lcrypto; \
    LD_LIBRARY_PATH=/opt/awslc/lib /tmp/awslc_preflight; \
    \
    if [ -x /opt/awslc/bin/openssl ]; then \
      LD_LIBRARY_PATH=/opt/awslc/lib /opt/awslc/bin/openssl version || true; \
    elif [ -x /opt/awslc/bin/bssl ]; then \
      LD_LIBRARY_PATH=/opt/awslc/lib /opt/awslc/bin/bssl version || true; \
    else \
      echo "[AWS-LC] CLI binary not found; compile/link smoke test passed"; \
    fi; \
    echo "[OK] AWS-LC build and link check passed"

# ---------------------------------------------------------
# 3) jemalloc
# ---------------------------------------------------------

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
      --disable-stats \
      --enable-readlinkat; \
    make -j"$(nproc)"; \
    make install; \
    strip -s /usr/local/lib/libjemalloc.so* || true; \
    ls -la /usr/local/lib/libjemalloc.so*

# ---------------------------------------------------------
# 4) cargo-c
# ---------------------------------------------------------

RUN set -eux; \
    curl -fsSL \
      "https://github.com/lu-zero/cargo-c/releases/download/${CARGOC_VERSION}/cargo-c-x86_64-unknown-linux-musl.tar.gz" \
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
    cargo cbuild --version; \
    cargo cinstall --version

# ---------------------------------------------------------
# 5) zlib-rs
# ---------------------------------------------------------

RUN --mount=type=cache,target=/root/.cargo/registry \
    --mount=type=cache,target=/root/.cargo/git \
    set -eux; \
    git clone --branch "${ZLIBRS_VERSION}" --depth=1 \
      https://github.com/trifectatechfoundation/zlib-rs.git /tmp/zlib-rs; \
    cd /tmp/zlib-rs/libz-rs-sys-cdylib; \
    export RUSTFLAGS="-C target-cpu=znver3 -C opt-level=3 -C codegen-units=1 -C lto=fat -C embed-bitcode=yes -C panic=abort -C linker=clang -C link-arg=-fuse-ld=lld -C link-arg=-Wl,--gc-sections"; \
    cargo cinstall --release --prefix=/usr/local --libdir=/usr/local/lib; \
    \
    if [ ! -f /usr/local/include/zlib.h ]; then \
      for candidate in \
        /usr/local/include/libz_rs/zlib.h \
        /usr/local/include/libz-rs/zlib.h \
        /usr/local/include/libz-rs-sys/zlib.h \
        /usr/local/include/libz-rs-sys-cdylib/zlib.h \
        /usr/local/include/zlib-rs/zlib.h \
        /usr/local/include/z-rs/zlib.h; do \
        if [ -f "${candidate}" ]; then \
          cp "${candidate}" /usr/local/include/zlib.h; \
          break; \
        fi; \
      done; \
    fi; \
    \
    if [ ! -f /usr/local/include/zlib.h ]; then \
      SRC_ZLIB_H="$(find /tmp/zlib-rs -type f -name 'zlib.h' | head -n1)"; \
      test -n "${SRC_ZLIB_H}"; \
      cp "${SRC_ZLIB_H}" /usr/local/include/zlib.h; \
    fi; \
    \
    if [ ! -f /usr/local/include/zconf.h ]; then \
      for candidate in \
        /usr/local/include/libz_rs/zconf.h \
        /usr/local/include/libz-rs/zconf.h \
        /usr/local/include/libz-rs-sys/zconf.h \
        /usr/local/include/libz-rs-sys-cdylib/zconf.h \
        /usr/local/include/zlib-rs/zconf.h \
        /usr/local/include/z-rs/zconf.h; do \
        if [ -f "${candidate}" ]; then \
          cp "${candidate}" /usr/local/include/zconf.h; \
          break; \
        fi; \
      done; \
    fi; \
    \
    if [ ! -f /usr/local/include/zconf.h ]; then \
      SRC_ZCONF_H="$(find /tmp/zlib-rs -type f -name 'zconf.h' 2>/dev/null | head -n1 || true)"; \
      if [ -n "${SRC_ZCONF_H}" ]; then \
        cp "${SRC_ZCONF_H}" /usr/local/include/zconf.h; \
      fi; \
    fi; \
    \
    test -f /usr/local/include/zlib.h; \
    \
    cd /usr/local/lib; \
    REAL_SO=""; \
    if [ -f libz_rs.so ] && [ ! -L libz_rs.so ]; then \
      REAL_SO="libz_rs.so"; \
    elif [ -L libz_rs.so ]; then \
      REAL_SO="$(basename "$(readlink -f libz_rs.so)")"; \
    else \
      REAL_SO="$(find . -maxdepth 1 -type f -name 'libz_rs.so*' -printf '%f\n' | head -n1)"; \
    fi; \
    test -n "${REAL_SO}"; \
    test -f "/usr/local/lib/${REAL_SO}"; \
    install -Dm755 "/usr/local/lib/${REAL_SO}" /usr/local/lib/libz.so.1.0.0; \
    patchelf --set-soname libz.so.1 /usr/local/lib/libz.so.1.0.0; \
    ln -sf libz.so.1.0.0 /usr/local/lib/libz.so.1; \
    ln -sf libz.so.1.0.0 /usr/local/lib/libz.so; \
    ln -sf libz.so.1.0.0 /usr/local/lib/libz_rs.so; \
    strip --strip-debug /usr/local/lib/libz.so.1.0.0 || true; \
    \
    printf '%s\n' \
      '#include <string.h>' \
      '#include <zlib.h>' \
      'int main(void) {' \
      '    z_stream z;' \
      '    memset(&z, 0, sizeof(z));' \
      '    if (deflateInit(&z, Z_DEFAULT_COMPRESSION) != Z_OK) return 1;' \
      '    deflate(&z, Z_NO_FLUSH);' \
      '    deflateEnd(&z);' \
      '    return 0;' \
      '}' \
      > /tmp/zlib_preflight.c; \
    clang -I/usr/local/include -L/usr/local/lib -fuse-ld=lld \
      -o /tmp/zlib_preflight /tmp/zlib_preflight.c -lz; \
    LD_LIBRARY_PATH=/usr/local/lib /tmp/zlib_preflight; \
    echo "[OK] zlib-rs compile/link/run preflight passed"

# ---------------------------------------------------------
# 6) zstd
# ---------------------------------------------------------

RUN set -eux; \
    wget -qO "zstd-${ZSTD_VERSION}.tar.gz" \
      "https://github.com/facebook/zstd/releases/download/v${ZSTD_VERSION}/zstd-${ZSTD_VERSION}.tar.gz"; \
    echo "${ZSTD_SHA256}  zstd-${ZSTD_VERSION}.tar.gz" | sha256sum -c -; \
    tar -xzf "zstd-${ZSTD_VERSION}.tar.gz"; \
    cd "zstd-${ZSTD_VERSION}"; \
    CFLAGS="${CPU_FLAGS} ${LTO_FLAGS}" \
    LDFLAGS="-fuse-ld=lld ${LTO_FLAGS} -Wl,--gc-sections" \
    make -j"$(nproc)" install PREFIX=/usr/local; \
    strip -s /usr/local/lib/libzstd.so* || true; \
    ls -la /usr/local/lib/libzstd.so*

# ---------------------------------------------------------
# 7) ngx_brotli + brotli libs
# ---------------------------------------------------------

RUN set -eux; \
    git clone --filter=blob:none https://github.com/google/ngx_brotli.git /tmp/ngx_brotli; \
    cd /tmp/ngx_brotli; \
    git checkout "${NGX_BROTLI_REF}"; \
    git submodule update --init --recursive --filter=blob:none

RUN set -eux; \
    cmake -S /tmp/ngx_brotli/deps/brotli -B /tmp/ngx_brotli/deps/brotli/out -GNinja \
      -DCMAKE_BUILD_TYPE=Release \
      -DBUILD_SHARED_LIBS=ON \
      -DCMAKE_INSTALL_PREFIX=/usr/local \
      -DCMAKE_INSTALL_LIBDIR=lib \
      -DCMAKE_C_COMPILER=clang \
      -DCMAKE_CXX_COMPILER=clang++ \
      -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=ON \
      -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
      -DCMAKE_C_FLAGS="${CPU_FLAGS} ${LTO_FLAGS}" \
      -DCMAKE_CXX_FLAGS="${CPU_FLAGS} ${LTO_FLAGS}" \
      -DCMAKE_EXE_LINKER_FLAGS="-fuse-ld=lld ${LTO_FLAGS} -Wl,--gc-sections" \
      -DCMAKE_SHARED_LINKER_FLAGS="-fuse-ld=lld ${LTO_FLAGS} -Wl,--gc-sections"; \
    cmake --build /tmp/ngx_brotli/deps/brotli/out --parallel; \
    cmake --install /tmp/ngx_brotli/deps/brotli/out; \
    strip -s /usr/local/lib/libbrotli*.so* || true; \
    ls -la /usr/local/lib/libbrotli*.so*

# ---------------------------------------------------------
# 8) ngx_http_zstd_module
# ---------------------------------------------------------

RUN set -eux; \
    git clone --branch "${NGX_ZSTD_MODULE_VERSION}" --depth=1 \
      https://github.com/HanadaLee/ngx_http_zstd_module.git /tmp/ngx_http_zstd_module; \
    sed -i 's/-l:libzstd.a/-lzstd/g' /tmp/ngx_http_zstd_module/config; \
    grep -n "zstd" /tmp/ngx_http_zstd_module/config || true

# ---------------------------------------------------------
# 9) NGINX
# ---------------------------------------------------------

RUN set -eux; \
    curl -fSL "https://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz" \
      -o "nginx-${NGINX_VERSION}.tar.gz"; \
    echo "${NGINX_SHA256}  nginx-${NGINX_VERSION}.tar.gz" | sha256sum -c -; \
    tar -xzf "nginx-${NGINX_VERSION}.tar.gz"; \
    mv "nginx-${NGINX_VERSION}" /tmp/nginx; \
    cd /tmp/nginx; \
    \
    test -f /usr/local/include/zlib.h; \
    test -f /usr/local/lib/libz.so; \
    test -f /usr/local/lib/libpcre2-8.so; \
    test -f /usr/local/lib/libzstd.so; \
    test -f /opt/awslc/lib/libssl.so; \
    test -f /opt/awslc/lib/libcrypto.so; \
    \
    export PKG_CONFIG_PATH="/usr/local/lib/pkgconfig:/usr/local/lib64/pkgconfig:/opt/awslc/lib/pkgconfig"; \
    \
    LD_OPT="-fuse-ld=lld ${LTO_FLAGS}"; \
    LD_OPT="${LD_OPT} -Wl,-O3 -Wl,--as-needed -Wl,--gc-sections"; \
    LD_OPT="${LD_OPT} -Wl,-z,relro -Wl,-z,now -Wl,-z,noexecstack"; \
    LD_OPT="${LD_OPT} -Wl,-rpath,/opt/awslc/lib:/usr/local/lib"; \
    LD_OPT="${LD_OPT} -L/opt/awslc/lib -L/usr/local/lib"; \
    LD_OPT="${LD_OPT} -lssl -lcrypto -lpcre2-8 -lz -lzstd"; \
    LD_OPT="${LD_OPT} -lbrotlienc -lbrotlicommon"; \
    \
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
      --user=nginx \
      --group=nginx \
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
      --without-http_fastcgi_module \
      --without-http_uwsgi_module \
      --without-http_scgi_module \
      --without-http_grpc_module \
      --without-http_memcached_module \
      --without-http_ssi_module \
      --without-http_userid_module \
      --without-http_autoindex_module \
      --without-http_empty_gif_module \
      --without-http_browser_module \
      --add-module=/tmp/ngx_brotli \
      --add-module=/tmp/ngx_http_zstd_module \
      --with-cc-opt="${CPU_FLAGS} ${LTO_FLAGS} -I/opt/awslc/include -I/usr/local/include" \
      --with-ld-opt="${LD_OPT}"; \
    make -j"$(nproc)"; \
    make install; \
    \
    if nm /usr/sbin/nginx 2>/dev/null | grep -Eqi 'ngx_.*quic|http_v3|quic'; then \
      echo "[OK] QUIC/HTTP3 related symbols found by nm"; \
    else \
      echo "[INFO] QUIC/HTTP3 symbol string not found by nm; LTO/internalized symbols can hide this"; \
    fi; \
    \
    strip -s /usr/sbin/nginx; \
    if compgen -G "/usr/lib/nginx/modules/*.so" > /dev/null; then \
      strip -s /usr/lib/nginx/modules/*.so || true; \
    fi; \
    \
    nginx -V 2>&1 | tee /tmp/nginx-build-version.txt; \
    grep -q -- '--with-http_v3_module' /tmp/nginx-build-version.txt; \
    grep -q -- '--with-http_v2_module' /tmp/nginx-build-version.txt; \
    grep -q -- '--with-pcre-jit' /tmp/nginx-build-version.txt; \
    grep -q -- '--with-threads' /tmp/nginx-build-version.txt; \
    grep -q -- '--with-file-aio' /tmp/nginx-build-version.txt; \
    grep -q -- '--add-module=/tmp/ngx_brotli' /tmp/nginx-build-version.txt; \
    grep -q -- '--add-module=/tmp/ngx_http_zstd_module' /tmp/nginx-build-version.txt; \
    \
    ldd /usr/sbin/nginx | tee /tmp/builder_ldd.txt; \
    ! grep -q "not found" /tmp/builder_ldd.txt; \
    echo "[OK] NGINX build passed"

# =========================================================
# Runtime
# =========================================================

FROM debian:trixie-slim@${DEBIAN_TRIXIE_DIGEST} AS runtime

ARG NGINX_VERSION
ARG AWSLC_VERSION
ARG ZLIBRS_VERSION
ARG CARGOC_VERSION
ARG ZSTD_VERSION
ARG NGX_BROTLI_REF
ARG JEMALLOC_VERSION
ARG PCRE2_VERSION
ARG NGX_ZSTD_MODULE_VERSION
ARG JBS_NGINX_WORKER_PROCESSES
ARG JBS_NGINX_WORKER_PROCESSES_MAX
ARG JBS_USE_JEMALLOC

ENV DEBIAN_FRONTEND=noninteractive

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
      ca-certificates; \
    rm -rf \
      /var/lib/apt/lists/* \
      /usr/share/doc \
      /usr/share/man \
      /usr/share/info \
      /usr/share/lintian \
      /usr/share/linda

COPY --link --from=builder /usr/sbin/nginx /usr/sbin/nginx
COPY --link --from=builder /etc/nginx /etc/nginx

COPY --link --from=builder /usr/local/lib/libpcre2-8.so* /usr/local/lib/
COPY --link --from=builder /usr/local/lib/libjemalloc.so.2 /usr/local/lib/
COPY --link --from=builder /usr/local/lib/libzstd.so* /usr/local/lib/
COPY --link --from=builder /usr/local/lib/libbrotli*.so* /usr/local/lib/
COPY --link --from=builder /usr/local/lib/libz.so.1.0.0 /usr/local/lib/

COPY --link --from=builder /opt/awslc/lib/libssl.so* /opt/awslc/lib/
COPY --link --from=builder /opt/awslc/lib/libcrypto.so* /opt/awslc/lib/

ENV MALLOC_CONF="abort_conf:true,background_thread:true,metadata_thp:auto,percpu_arena:phycpu,tcache:true,tcache_max:32768,dirty_decay_ms:30000,muzzy_decay_ms:30000" \
    NGINX_ENTRYPOINT_QUIET_LOGS=1 \
    JBS_USE_JEMALLOC=${JBS_USE_JEMALLOC} \
    JBS_NGINX_WORKER_PROCESSES=${JBS_NGINX_WORKER_PROCESSES} \
    JBS_NGINX_WORKER_PROCESSES_MAX=${JBS_NGINX_WORKER_PROCESSES_MAX}

RUN set -eux; \
    printf '%s\n' \
      'nginx:x:101:101:nginx:/nonexistent:/usr/sbin/nologin' \
      >> /etc/passwd; \
    printf '%s\n' \
      'nginx:x:101:' \
      >> /etc/group; \
    mkdir -p \
      /var/log/nginx \
      /var/cache/nginx/client_temp \
      /var/cache/nginx/proxy_temp \
      /var/cache/nginx/fastcgi_temp \
      /var/cache/nginx/uwsgi_temp \
      /var/cache/nginx/scgi_temp \
      /var/cache/nginx/navidrome \
      /run \
      /opt/awslc/lib \
      /usr/local/lib; \
    chown -R nginx:nginx /etc/nginx /var/log/nginx /var/cache/nginx; \
    rm -rf /etc/nginx/logs; \
    ln -sf /var/log/nginx /etc/nginx/logs; \
    ln -sf /dev/stdout /var/log/nginx/access.log; \
    ln -sf /dev/stderr /var/log/nginx/error.log; \
    ln -sf libz.so.1.0.0 /usr/local/lib/libz.so.1; \
    ln -sf libz.so.1.0.0 /usr/local/lib/libz.so; \
    printf "/usr/local/lib\n/opt/awslc/lib\n" > /etc/ld.so.conf.d/jbs-custom-libs.conf; \
    ldconfig; \
    \
    ldd /usr/sbin/nginx | tee /tmp/runtime_ldd.txt; \
    ! grep -q "not found" /tmp/runtime_ldd.txt; \
    nginx -V; \
    nginx -t; \
    rm -f /tmp/runtime_ldd.txt

RUN cat > /entrypoint <<'SH'
#!/bin/sh
set -eu

is_true() {
    case "${1:-}" in
        1|true|TRUE|True|yes|YES|Yes|on|ON|On)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

is_auto() {
    case "${1:-}" in
        ""|auto|AUTO|Auto)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

valid_uint() {
    case "${1:-}" in
        ""|*[!0-9]*)
            return 1
            ;;
        *)
            return 0
            ;;
    esac
}

detect_cpu_cores() {
    if [ -r /sys/fs/cgroup/cpu.max ]; then
        read -r quota period < /sys/fs/cgroup/cpu.max || true

        if valid_uint "${quota:-}" && valid_uint "${period:-}" && [ "$period" -gt 0 ] 2>/dev/null; then
            cores=$(( (quota + period - 1) / period ))
            if [ "$cores" -lt 1 ]; then
                cores=1
            fi
            echo "$cores"
            return 0
        fi
    fi

    cores="$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)"
    if ! valid_uint "$cores" || [ "$cores" -lt 1 ] 2>/dev/null; then
        cores=1
    fi

    echo "$cores"
}

cap_uint() {
    value="$1"
    min="$2"
    max="$3"

    if ! valid_uint "$value"; then
        value="$min"
    fi

    if [ "$value" -lt "$min" ] 2>/dev/null; then
        value="$min"
    fi

    if valid_uint "$max" && [ "$max" -gt 0 ] 2>/dev/null && [ "$value" -gt "$max" ] 2>/dev/null; then
        value="$max"
    fi

    echo "$value"
}

configure_workers() {
    conf="${NGINX_CONF:-/etc/nginx/nginx.conf}"

    if [ ! -f "$conf" ]; then
        return 0
    fi

    wanted="${JBS_NGINX_WORKER_PROCESSES:-auto}"

    if is_auto "$wanted"; then
        cores="$(detect_cpu_cores)"
        max="${JBS_NGINX_WORKER_PROCESSES_MAX:-8}"

        if ! valid_uint "$max" || [ "$max" -lt 1 ] 2>/dev/null; then
            max=8
        fi

        workers="$(cap_uint "$cores" 1 "$max")"
    else
        workers="$(cap_uint "$wanted" 1 "${JBS_NGINX_WORKER_PROCESSES_MAX:-8}")"
    fi

    if grep -qE '^[[:space:]]*worker_processes[[:space:]]+' "$conf"; then
        sed -i "s/^[[:space:]]*worker_processes[[:space:]].*/worker_processes ${workers};/" "$conf"
    else
        tmp="${conf}.tmp"
        printf 'worker_processes %s;\n' "$workers" > "$tmp"
        cat "$conf" >> "$tmp"
        cat "$tmp" > "$conf"
        rm -f "$tmp"
    fi

    echo "[entrypoint] worker_processes=${workers}" >&2
}

configure_allocator() {
    unset LD_PRELOAD

    if ! is_true "${JBS_USE_JEMALLOC:-true}"; then
        echo "[entrypoint] jemalloc disabled" >&2
        return 0
    fi

    if [ ! -r /usr/local/lib/libjemalloc.so.2 ]; then
        echo "[entrypoint] jemalloc not found; using system allocator" >&2
        return 0
    fi

    set +e
    LD_PRELOAD=/usr/local/lib/libjemalloc.so.2 /bin/true >/dev/null 2>&1
    code="$?"
    set -e

    if [ "$code" -ne 0 ]; then
        echo "[entrypoint] jemalloc preload test failed status=${code}; using system allocator" >&2
        unset LD_PRELOAD
        return 0
    fi

    export LD_PRELOAD=/usr/local/lib/libjemalloc.so.2
    echo "[entrypoint] jemalloc enabled" >&2
}

configure_workers
configure_allocator

exec "$@"
SH

RUN chmod 755 /entrypoint && \
    /bin/sh -n /entrypoint && \
    /entrypoint nginx -t

EXPOSE 80 443/tcp 443/udp

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD nginx -t -q || exit 1

STOPSIGNAL SIGQUIT

LABEL project="JBS Networks NGINX 5.2 Resource-Aware Mainline" \
      nginx.version="${NGINX_VERSION}" \
      pcre2.version="${PCRE2_VERSION}" \
      awslc.version="${AWSLC_VERSION}" \
      zlib-rs.version="${ZLIBRS_VERSION}" \
      cargo-c.version="${CARGOC_VERSION}" \
      zstd.version="${ZSTD_VERSION}" \
      jemalloc.version="${JEMALLOC_VERSION}" \
      ngx_brotli.ref="${NGX_BROTLI_REF}" \
      ngx_zstd.version="${NGX_ZSTD_MODULE_VERSION}" \
      runtime.mode="rootful-container-root-master-nginx-workers" \
      optimization="Znver3/Clang/LLD/Full-LTO/AWS-LC-5.x-IPO/Jemalloc-SafeFallback/zlib-rs-fat-LTO/Brotli-IPO/Zstd/HTTP3/ReverseProxy-Trimmed/Resource-Aware"

ENTRYPOINT ["/entrypoint"]

CMD ["nginx", "-g", "daemon off;"]
