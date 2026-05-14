# syntax=docker/dockerfile:1.7

# =========================================================
# JBS Networks NGINX 5.1 - Latest Dependency Refresh / Relaxed Safe Checks
# 기준일: 2026-05-14
#
# 핵심 방향:
#  - rootless Docker 아님
#  - 컨테이너 / nginx master는 root로 시작
#  - nginx worker는 nginx.conf의 `user nginx;`로 권한 drop
#  - setcap 미사용: LD_PRELOAD=jemalloc secure-exec 문제 회피
#  - USER nginx 미사용: 80/443 바인딩, QUIC, jemalloc 안정성 우선
#
# 주요 버전:
#  - 검증: scripts/check_media_stack_versions.sh
#  - NGINX 1.30.1
#  - AWS-LC v1.73.0
#  - PCRE2 10.47
#  - jemalloc 5.3.1
#  - zlib-rs 0.6.3
#  - cargo-c 0.10.22
#  - zstd 1.5.7
# =========================================================

ARG DEBIAN_TRIXIE_DIGEST="sha256:cedb1ef40439206b673ee8b33a46a03a0c9fa90bf3732f54704f99cb061d2c5a"

ARG NGINX_VERSION=1.30.1
ARG NGINX_SHA256=99765000d974896b31ca5882d8c279ce3fe7ef6f5c6f9f0a967ed7fd3407f9cc

ARG PCRE2_VERSION=10.47
ARG PCRE2_SHA256=c08ae2388ef333e8403e670ad70c0a11f1eed021fd88308d7e02f596fcd9dc16

ARG AWSLC_VERSION=v1.73.0

ARG JEMALLOC_VERSION=5.3.1
ARG JEMALLOC_SHA256=3826bc80232f22ed5c4662f3034f799ca316e819103bdc7bb99018a421706f92

ARG ZLIBRS_VERSION=v0.6.3
ARG CARGOC_VERSION=v0.10.22

ARG ZSTD_VERSION=1.5.7
ARG ZSTD_SHA256=eb33e51f49a15e023950cd7825ca74a4a2b43db8354825ac24fc1b7ee09e6fa3

ARG NGX_ZSTD_MODULE_VERSION=0.1.1
ARG NGX_BROTLI_REF=a71f9312c2deb28875acc7bacfdd5695a111aa53

ARG CPU_FLAGS="-O3 -march=znver3 -mtune=znver3 -pipe -fstack-protector-strong -D_FORTIFY_SOURCE=3 -ffunction-sections -fdata-sections -fno-semantic-interposition -DNDEBUG"
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

# LD=ld.lld는 의도적으로 지정하지 않음.
# autoconf/make 일부가 clang driver 없이 raw ld.lld를 직접 호출하면 LTO 링크가 깨질 수 있음.
# 링커 선택은 LDFLAGS / CMAKE_*_LINKER_FLAGS의 -fuse-ld=lld로만 처리.
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
    rm -rf /var/lib/apt/lists/*

WORKDIR /tmp

# ---------------------------------------------------------
# 1) PCRE2 10.47
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
# 2) AWS-LC v1.73.0
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
      -DCMAKE_C_FLAGS="${CPU_FLAGS} ${LTO_FLAGS} -fPIC" \
      -DCMAKE_CXX_FLAGS="${CPU_FLAGS} ${LTO_FLAGS} -fPIC" \
      -DCMAKE_SHARED_LINKER_FLAGS="-fuse-ld=lld ${LTO_FLAGS} -Wl,--gc-sections"; \
    ninja -C /tmp/aws-lc/build install; \
    strip -s /opt/awslc/lib/libssl.so* /opt/awslc/lib/libcrypto.so* || true; \
    \
    test -f /opt/awslc/lib/libssl.so; \
    test -f /opt/awslc/lib/libcrypto.so; \
    \
    echo "=== AWS-LC library files ==="; \
    ls -la /opt/awslc/lib/libssl.so* /opt/awslc/lib/libcrypto.so*; \
    \
    echo "=== AWS-LC dynamic symbols soft preview ==="; \
    nm -D /opt/awslc/lib/libssl.so 2>/dev/null | head -n 30 || true; \
    nm -D /opt/awslc/lib/libcrypto.so 2>/dev/null | head -n 30 || true; \
    \
    echo "=== AWS-LC compile/link/run smoke test ==="; \
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
    echo "=== AWS-LC CLI optional check ==="; \
    if [ -x /opt/awslc/bin/openssl ]; then \
      LD_LIBRARY_PATH=/opt/awslc/lib /opt/awslc/bin/openssl version || true; \
    elif [ -x /opt/awslc/bin/bssl ]; then \
      LD_LIBRARY_PATH=/opt/awslc/lib /opt/awslc/bin/bssl version || true; \
    else \
      echo "[AWS-LC] CLI binary not found; compile/link smoke test passed"; \
    fi; \
    echo "[OK] AWS-LC build and link check passed"

# ---------------------------------------------------------
# 3) jemalloc 5.3.1
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
# 4) cargo-c v0.10.22
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
# 5) zlib-rs v0.6.3
# ---------------------------------------------------------
RUN --mount=type=cache,target=/root/.cargo/registry \
    --mount=type=cache,target=/root/.cargo/git \
    set -eux; \
    git clone --branch "${ZLIBRS_VERSION}" --depth=1 \
      https://github.com/trifectatechfoundation/zlib-rs.git /tmp/zlib-rs; \
    cd /tmp/zlib-rs/libz-rs-sys-cdylib; \
    export RUSTFLAGS="-C target-cpu=znver3 -C opt-level=3 -C codegen-units=1"; \
    cargo cinstall --release --prefix=/usr/local --libdir=/usr/local/lib; \
    \
    echo "=== zlib-rs installed headers ==="; \
    find /usr/local/include -type f -name '*.h' | sort || true; \
    echo "=== zlib-rs installed libs ==="; \
    find /usr/local/lib -maxdepth 2 -type f \( -name 'libz*' -o -name '*.pc' \) | sort || true; \
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
          echo "[zlib-rs] using zlib.h from ${candidate}"; \
          cp "${candidate}" /usr/local/include/zlib.h; \
          break; \
        fi; \
      done; \
    fi; \
    \
    if [ ! -f /usr/local/include/zlib.h ]; then \
      SRC_ZLIB_H="$(find /tmp/zlib-rs -type f -name 'zlib.h' | head -n1)"; \
      test -n "${SRC_ZLIB_H}"; \
      echo "[zlib-rs] fallback zlib.h=${SRC_ZLIB_H}"; \
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
          echo "[zlib-rs] using zconf.h from ${candidate}"; \
          cp "${candidate}" /usr/local/include/zconf.h; \
          break; \
        fi; \
      done; \
    fi; \
    \
    if [ ! -f /usr/local/include/zconf.h ]; then \
      SRC_ZCONF_H="$(find /tmp/zlib-rs -type f -name 'zconf.h' 2>/dev/null | head -n1 || true)"; \
      if [ -n "${SRC_ZCONF_H}" ]; then \
        echo "[zlib-rs] fallback zconf.h=${SRC_ZCONF_H}"; \
        cp "${SRC_ZCONF_H}" /usr/local/include/zconf.h; \
      else \
        echo "[zlib-rs] no zconf.h found; zlib.h may be self-contained"; \
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
    echo "[zlib-rs] real so file: ${REAL_SO}"; \
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
# 6) zstd 1.5.7
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
      -DCMAKE_C_FLAGS="${CPU_FLAGS} ${LTO_FLAGS}" \
      -DCMAKE_CXX_FLAGS="${CPU_FLAGS} ${LTO_FLAGS}" \
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
# 9) NGINX 1.30.1
# ---------------------------------------------------------
RUN set -eux; \
    curl -fSL "https://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz" \
      -o "nginx-${NGINX_VERSION}.tar.gz"; \
    echo "${NGINX_SHA256}  nginx-${NGINX_VERSION}.tar.gz" | sha256sum -c -; \
    tar -xzf "nginx-${NGINX_VERSION}.tar.gz"; \
    mv "nginx-${NGINX_VERSION}" /tmp/nginx; \
    cd /tmp/nginx; \
    \
    echo "=== pre-nginx dependency check ==="; \
    test -f /usr/local/include/zlib.h; \
    ls -la /usr/local/lib/libz*; \
    ls -la /usr/local/lib/libpcre2-8.so*; \
    ls -la /usr/local/lib/libzstd.so*; \
    ls -la /usr/local/lib/libbrotli*.so*; \
    ls -la /opt/awslc/lib/libssl.so* /opt/awslc/lib/libcrypto.so*; \
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
      --add-module=/tmp/ngx_brotli \
      --add-module=/tmp/ngx_http_zstd_module \
      --with-cc-opt="${CPU_FLAGS} ${LTO_FLAGS} -I/opt/awslc/include -I/usr/local/include" \
      --with-ld-opt="${LD_OPT}"; \
    make -j"$(nproc)"; \
    make install; \
    \
    echo "=== HTTP/3 QUIC symbol soft check before strip ==="; \
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
    \
    echo "=== required module/configure flag verification ==="; \
    grep -q -- '--with-http_v3_module' /tmp/nginx-build-version.txt; \
    grep -q -- '--with-http_v2_module' /tmp/nginx-build-version.txt; \
    grep -q -- '--with-pcre-jit' /tmp/nginx-build-version.txt; \
    grep -q -- '--with-threads' /tmp/nginx-build-version.txt; \
    grep -q -- '--with-file-aio' /tmp/nginx-build-version.txt; \
    grep -q -- '--add-module=/tmp/ngx_brotli' /tmp/nginx-build-version.txt; \
    grep -q -- '--add-module=/tmp/ngx_http_zstd_module' /tmp/nginx-build-version.txt; \
    echo "[OK] all required modules/configure flags verified"; \
    \
    ldd /usr/sbin/nginx | tee /tmp/builder_ldd.txt; \
    ! grep -q "not found" /tmp/builder_ldd.txt

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

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN set -eux; \
    apt-get update; \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      ca-certificates \
      curl; \
    rm -rf /var/lib/apt/lists/*

RUN set -eux; \
    if ! getent group nginx >/dev/null; then \
      groupadd --system --gid 101 nginx || groupadd --system nginx; \
    fi; \
    if ! id -u nginx >/dev/null 2>&1; then \
      useradd --system --uid 101 --gid nginx --no-log-init --shell /usr/sbin/nologin nginx \
      || useradd --system --gid nginx --no-log-init --shell /usr/sbin/nologin nginx; \
    fi

COPY --link --from=builder /usr/sbin/nginx /usr/sbin/nginx
COPY --link --from=builder /etc/nginx /etc/nginx

COPY --link --from=builder /usr/local/lib/libpcre2-8.so*    /usr/local/lib/
COPY --link --from=builder /usr/local/lib/libjemalloc.so*   /usr/local/lib/
COPY --link --from=builder /usr/local/lib/libzstd.so*       /usr/local/lib/
COPY --link --from=builder /usr/local/lib/libbrotli*.so*    /usr/local/lib/
COPY --link --from=builder /usr/local/lib/libz.so.1.0.0     /usr/local/lib/

COPY --link --from=builder /opt/awslc/lib/libssl.so*        /opt/awslc/lib/
COPY --link --from=builder /opt/awslc/lib/libcrypto.so*     /opt/awslc/lib/

ENV LD_PRELOAD="/usr/local/lib/libjemalloc.so.2" \
    MALLOC_CONF="abort_conf:true,background_thread:true,metadata_thp:auto,percpu_arena:phycpu,tcache_max:32768,dirty_decay_ms:30000,muzzy_decay_ms:30000" \
    NGINX_ENTRYPOINT_QUIET_LOGS=1

RUN set -eux; \
    mkdir -p \
      /var/log/nginx \
      /var/cache/nginx/client_temp \
      /var/cache/nginx/proxy_temp \
      /var/cache/nginx/fastcgi_temp \
      /var/cache/nginx/uwsgi_temp \
      /var/cache/nginx/scgi_temp \
      /var/cache/nginx/navidrome \
      /run; \
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
    echo "=== runtime ldd verification ==="; \
    ldd /usr/sbin/nginx | tee /tmp/runtime_ldd.txt; \
    ! grep -q "not found" /tmp/runtime_ldd.txt; \
    \
    echo "=== nginx -V ==="; \
    nginx -V; \
    \
    echo "=== jemalloc LD_PRELOAD soft check ==="; \
    LD_TRACE_LOADED_OBJECTS=1 /usr/sbin/nginx 2>&1 | grep -qi jemalloc \
      && echo "[OK] jemalloc confirmed in LD_TRACE output" \
      || echo "[INFO] jemalloc not in LD_TRACE output; continuing to real runtime check"; \
    \
    echo "=== nginx config test with LD_PRELOAD + MALLOC_CONF ==="; \
    nginx -t; \
    \
    echo "=== jemalloc real process maps hard check ==="; \
    nginx; \
    sleep 0.5; \
    NGINX_PID="$(cat /var/run/nginx.pid)"; \
    grep -qi jemalloc "/proc/${NGINX_PID}/maps" \
      && echo "[OK] jemalloc confirmed in running nginx master maps" \
      || { echo "[ERROR] jemalloc not found in running nginx master maps" >&2; nginx -s quit || true; exit 1; }; \
    nginx -s quit; \
    sleep 0.5

EXPOSE 80 443/tcp 443/udp

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD curl -fsS --max-time 2 http://127.0.0.1/nginx-health -o /dev/null || curl -fsS --max-time 2 http://127.0.0.1/ -o /dev/null || exit 1

STOPSIGNAL SIGQUIT

LABEL project="JBS Networks NGINX 5.1 Latest Stable" \
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
      optimization="Znver3/Clang/LLD/Full-LTO/AWS-LC/Jemalloc/zlib-rs/Brotli/Zstd/HTTP3"

CMD ["nginx", "-g", "daemon off;"]
