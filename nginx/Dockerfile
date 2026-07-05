# syntax=docker/dockerfile:1.7

# =========================================================
# JBS Networks NGINX 5.4 Synergy Lite v3
# Target: 1 vCPU / 1GB RAM / AMD EPYC Zen1
#
# 방향:
#  - Zen1 최적화: znver3 제거, znver1 + 128-bit vector 선호
#  - Low RSS: jemalloc arena/tcache/decay 축소
#  - Low binary surface: 미사용 stream/slice/gunzip/stub_status 제거
#  - 미사용 CDN 관련 설정 제거
#  - Cloudflare real-ip include는 유지
#  - map / realip / proxy_cache / limit_req / limit_conn / gzip / brotli / zstd / HTTP2 / HTTP3 유지
#  - thread_pool / aio threads / directio 미사용
#  - LD_PRELOAD 제거, jemalloc 직접 링크
# =========================================================

ARG DEBIAN_TRIXIE_DIGEST="sha256:28de0877c2189802884ccd20f15ee41c203573bd87bb6b883f5f46362d24c5c2"

ARG NGINX_VERSION=1.31.2

ARG PCRE2_VERSION=10.47
ARG PCRE2_SHA256=c08ae2388ef333e8403e670ad70c0a11f1eed021fd88308d7e02f596fcd9dc16

ARG AWSLC_VERSION=v5.1.0

ARG JEMALLOC_VERSION=5.3.1
ARG JEMALLOC_SHA256=3826bc80232f22ed5c4662f3034f799ca316e819103bdc7bb99018a421706f92

ARG ZLIBRS_VERSION=v0.6.5
ARG CARGOC_VERSION=v0.10.23
ARG CARGOC_X86_64_MUSL_SHA256=603d6a9a25710220d631f0f7ace0e9922d5a69425eb4f1fbcbf6339b357f6d5f

ARG ZSTD_VERSION=1.5.7
ARG ZSTD_SHA256=eb33e51f49a15e023950cd7825ca74a4a2b43db8354825ac24fc1b7ee09e6fa3

ARG NGX_ZSTD_MODULE_VERSION=0.1.1
ARG NGX_BROTLI_REF=a71f9312c2deb28875acc7bacfdd5695a111aa53

# Zen1/Naples용: znver3는 제거.
# Zen1은 256-bit AVX를 내부적으로 128-bit로 처리하는 편이라 128-bit vector 선호.
ARG CPU_FLAGS="-O2 -march=znver1 -mtune=znver1 -mprefer-vector-width=128 -pipe \
 -fstack-protector-strong -fstack-clash-protection \
 -D_FORTIFY_SOURCE=3 \
 -ffunction-sections -fdata-sections \
 -fno-semantic-interposition -fno-plt -fomit-frame-pointer \
 -DNDEBUG"

# Full LTO보다 Thin LTO가 빌드 RAM/시간을 덜 먹고, 런타임 차이는 이 용도에서 작음.
ARG LTO_FLAGS="-flto=thin"

ARG LD_LIB="-fuse-ld=lld \
 -Wl,-O2 \
 -Wl,--as-needed -Wl,--gc-sections \
 -Wl,-z,relro -Wl,-z,now -Wl,-z,noexecstack"

ARG LD_NGINX="-fuse-ld=lld \
 -Wl,-O2 -Wl,--lto-O2 \
 -Wl,--as-needed -Wl,--gc-sections -Wl,--icf=safe \
 -Wl,--enable-new-dtags \
 -Wl,-z,relro -Wl,-z,now -Wl,-z,noexecstack \
 -Wl,-z,pack-relative-relocs -Wl,-z,separate-code"

# 1 worker / 1 vCPU 기준 저RSS 설정.
ARG JEMALLOC_MALLOC_CONF="abort_conf:true,narenas:1,background_thread:false,metadata_thp:disabled,percpu_arena:disabled,tcache:true,tcache_max:8192,dirty_decay_ms:1000,muzzy_decay_ms:5000,oversize_threshold:1048576,retain:false"

# =========================================================
# Builder
# =========================================================
FROM debian:trixie-slim@${DEBIAN_TRIXIE_DIGEST} AS builder

ARG TARGETARCH
ARG NGINX_VERSION
ARG PCRE2_VERSION
ARG PCRE2_SHA256
ARG AWSLC_VERSION
ARG JEMALLOC_VERSION
ARG JEMALLOC_SHA256
ARG JEMALLOC_MALLOC_CONF
ARG ZLIBRS_VERSION
ARG CARGOC_VERSION
ARG CARGOC_X86_64_MUSL_SHA256
ARG ZSTD_VERSION
ARG ZSTD_SHA256
ARG NGX_ZSTD_MODULE_VERSION
ARG NGX_BROTLI_REF
ARG CPU_FLAGS
ARG LTO_FLAGS
ARG LD_LIB
ARG LD_NGINX

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ENV DEBIAN_FRONTEND=noninteractive \
    CC=clang \
    CXX=clang++ \
    AR=llvm-ar \
    RANLIB=llvm-ranlib \
    NM=llvm-nm \
    LLVM_AR=llvm-ar \
    LLVM_RANLIB=llvm-ranlib \
    LLVM_NM=llvm-nm \
    CARGO_NET_GIT_FETCH_WITH_CLI=true

RUN case "${TARGETARCH:-amd64}" in \
      amd64|"") echo "Building for amd64 / znver1";; \
      *) echo "Unsupported TARGETARCH=${TARGETARCH}. This image is x86_64/Zen1 only." >&2; exit 1;; \
    esac

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    set -eux; \
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
      git \
      gnupg \
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
# 1) PCRE2 static
# ---------------------------------------------------------
RUN set -eux; \
    wget -qO "pcre2-${PCRE2_VERSION}.tar.gz" \
      "https://github.com/PCRE2Project/pcre2/releases/download/pcre2-${PCRE2_VERSION}/pcre2-${PCRE2_VERSION}.tar.gz"; \
    echo "${PCRE2_SHA256}  pcre2-${PCRE2_VERSION}.tar.gz" | sha256sum -c -; \
    tar -xzf "pcre2-${PCRE2_VERSION}.tar.gz"; \
    cd "pcre2-${PCRE2_VERSION}"; \
    CFLAGS="${CPU_FLAGS}" \
    LDFLAGS="-fuse-ld=lld -Wl,-O2 -Wl,--as-needed -Wl,-z,relro -Wl,-z,now -Wl,-z,noexecstack" \
    ./configure \
      --prefix=/usr/local \
      --enable-jit \
      --enable-static \
      --disable-shared \
      --disable-pcre2-16 \
      --disable-pcre2-32; \
    make -j"$(nproc)"; \
    make install; \
    test -f /usr/local/lib/libpcre2-8.a; \
    /usr/local/bin/pcre2-config --version; \
    rm -rf "/tmp/pcre2-${PCRE2_VERSION}" "/tmp/pcre2-${PCRE2_VERSION}.tar.gz"

# ---------------------------------------------------------
# 2) AWS-LC shared
# AWS-LC standalone build requires Go; keep golang in builder deps.
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
      -DCMAKE_AR=/usr/bin/llvm-ar \
      -DCMAKE_RANLIB=/usr/bin/llvm-ranlib \
      -DCMAKE_NM=/usr/bin/llvm-nm \
      -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=ON \
      -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
      -DCMAKE_C_FLAGS="${CPU_FLAGS} -fPIC" \
      -DCMAKE_CXX_FLAGS="${CPU_FLAGS} -fPIC" \
      -DCMAKE_EXE_LINKER_FLAGS="-fuse-ld=lld" \
      -DCMAKE_SHARED_LINKER_FLAGS="-fuse-ld=lld"; \
    ninja -C /tmp/aws-lc/build install; \
    find /opt/awslc/lib -maxdepth 2 -name '*.a' -delete; \
    strip -s /opt/awslc/lib/libssl.so* /opt/awslc/lib/libcrypto.so* || true; \
    test -f /opt/awslc/lib/libssl.so; \
    test -f /opt/awslc/lib/libcrypto.so; \
    printf '%s\n' \
      '#include <openssl/ssl.h>' \
      'int main(void) {' \
      '    SSL_CTX *ctx = SSL_CTX_new(TLS_method());' \
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
    rm -rf /tmp/aws-lc /tmp/awslc_preflight /tmp/awslc_preflight.c

# ---------------------------------------------------------
# 3) jemalloc shared, directly linked into nginx
# ---------------------------------------------------------
RUN set -eux; \
    wget -qO "jemalloc-${JEMALLOC_VERSION}.tar.bz2" \
      "https://github.com/jemalloc/jemalloc/releases/download/${JEMALLOC_VERSION}/jemalloc-${JEMALLOC_VERSION}.tar.bz2"; \
    echo "${JEMALLOC_SHA256}  jemalloc-${JEMALLOC_VERSION}.tar.bz2" | sha256sum -c -; \
    tar -xjf "jemalloc-${JEMALLOC_VERSION}.tar.bz2"; \
    cd "jemalloc-${JEMALLOC_VERSION}"; \
    CFLAGS="${CPU_FLAGS} ${LTO_FLAGS}" \
    LDFLAGS="${LD_LIB} ${LTO_FLAGS}" \
    ./configure \
      --prefix=/usr/local \
      --disable-cxx \
      --disable-stats \
      --enable-readlinkat \
      --with-malloc-conf="${JEMALLOC_MALLOC_CONF}"; \
    make -j"$(nproc)"; \
    make install; \
    strip -s /usr/local/lib/libjemalloc.so* || true; \
    test -f /usr/local/lib/libjemalloc.so.2; \
    rm -rf "/tmp/jemalloc-${JEMALLOC_VERSION}" "/tmp/jemalloc-${JEMALLOC_VERSION}.tar.bz2"

# ---------------------------------------------------------
# 4) cargo-c
# ---------------------------------------------------------
RUN set -eux; \
    curl -fsSL \
      "https://github.com/lu-zero/cargo-c/releases/download/${CARGOC_VERSION}/cargo-c-x86_64-unknown-linux-musl.tar.gz" \
      -o /tmp/cargo-c.tar.gz; \
    echo "${CARGOC_X86_64_MUSL_SHA256}  /tmp/cargo-c.tar.gz" | sha256sum -c -; \
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
    export RUSTFLAGS="-C target-cpu=znver1 -C opt-level=3 -C codegen-units=1 -C lto=thin -C embed-bitcode=yes -C panic=abort -C linker=clang -C link-arg=-fuse-ld=lld -C link-arg=-Wl,-O2 -C link-arg=-Wl,--gc-sections -C link-arg=-Wl,--icf=safe"; \
    cargo cinstall --release --prefix=/usr/local --libdir=/usr/local/lib; \
    if [ ! -f /usr/local/include/zlib.h ]; then \
      SRC_ZLIB_H="$(find /tmp/zlib-rs -type f -name 'zlib.h' | head -n1)"; \
      test -n "${SRC_ZLIB_H}"; \
      cp "${SRC_ZLIB_H}" /usr/local/include/zlib.h; \
    fi; \
    if [ ! -f /usr/local/include/zconf.h ]; then \
      SRC_ZCONF_H="$(find /tmp/zlib-rs -type f -name 'zconf.h' 2>/dev/null | head -n1 || true)"; \
      if [ -n "${SRC_ZCONF_H}" ]; then cp "${SRC_ZCONF_H}" /usr/local/include/zconf.h; fi; \
    fi; \
    test -f /usr/local/include/zlib.h; \
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
    install -Dm755 "/usr/local/lib/${REAL_SO}" /usr/local/lib/libz.so.1.0.0; \
    patchelf --set-soname libz.so.1 /usr/local/lib/libz.so.1.0.0; \
    ln -sf libz.so.1.0.0 /usr/local/lib/libz.so.1; \
    ln -sf libz.so.1.0.0 /usr/local/lib/libz.so; \
    ln -sf libz.so.1.0.0 /usr/local/lib/libz_rs.so; \
    strip --strip-debug /usr/local/lib/libz.so.1.0.0 || true; \
    printf '%s\n' \
      '#include <string.h>' \
      '#include <zlib.h>' \
      'int main(void) {' \
      '    z_stream z;' \
      '    memset(&z, 0, sizeof(z));' \
      '    if (deflateInit(&z, Z_DEFAULT_COMPRESSION) != Z_OK) return 1;' \
      '    deflateEnd(&z);' \
      '    return 0;' \
      '}' \
      > /tmp/zlib_preflight.c; \
    clang -I/usr/local/include -L/usr/local/lib -fuse-ld=lld \
      -o /tmp/zlib_preflight /tmp/zlib_preflight.c -lz; \
    LD_LIBRARY_PATH=/usr/local/lib /tmp/zlib_preflight; \
    rm -rf /tmp/zlib-rs /tmp/zlib_preflight /tmp/zlib_preflight.c

# ---------------------------------------------------------
# 6) zstd shared
# ---------------------------------------------------------
RUN set -eux; \
    wget -qO "zstd-${ZSTD_VERSION}.tar.gz" \
      "https://github.com/facebook/zstd/releases/download/v${ZSTD_VERSION}/zstd-${ZSTD_VERSION}.tar.gz"; \
    echo "${ZSTD_SHA256}  zstd-${ZSTD_VERSION}.tar.gz" | sha256sum -c -; \
    tar -xzf "zstd-${ZSTD_VERSION}.tar.gz"; \
    cmake -S "zstd-${ZSTD_VERSION}/build/cmake" -B /tmp/zstd-build -GNinja \
      -DCMAKE_BUILD_TYPE=Release \
      -DZSTD_BUILD_STATIC=OFF \
      -DZSTD_BUILD_SHARED=ON \
      -DZSTD_BUILD_PROGRAMS=OFF \
      -DZSTD_BUILD_TESTS=OFF \
      -DCMAKE_INSTALL_PREFIX=/usr/local \
      -DCMAKE_INSTALL_LIBDIR=lib \
      -DCMAKE_C_COMPILER=clang \
      -DCMAKE_CXX_COMPILER=clang++ \
      -DCMAKE_AR=/usr/bin/llvm-ar \
      -DCMAKE_RANLIB=/usr/bin/llvm-ranlib \
      -DCMAKE_NM=/usr/bin/llvm-nm \
      -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=ON \
      -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
      -DCMAKE_C_FLAGS="${CPU_FLAGS} -fPIC" \
      -DCMAKE_CXX_FLAGS="${CPU_FLAGS} -fPIC" \
      -DCMAKE_EXE_LINKER_FLAGS="${LD_LIB}" \
      -DCMAKE_SHARED_LINKER_FLAGS="${LD_LIB}"; \
    ninja -C /tmp/zstd-build install; \
    strip -s /usr/local/lib/libzstd.so* || true; \
    rm -rf "/tmp/zstd-${ZSTD_VERSION}" "/tmp/zstd-${ZSTD_VERSION}.tar.gz" /tmp/zstd-build

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
      -DCMAKE_AR=/usr/bin/llvm-ar \
      -DCMAKE_RANLIB=/usr/bin/llvm-ranlib \
      -DCMAKE_NM=/usr/bin/llvm-nm \
      -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=ON \
      -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
      -DCMAKE_C_FLAGS="${CPU_FLAGS}" \
      -DCMAKE_CXX_FLAGS="${CPU_FLAGS}" \
      -DCMAKE_EXE_LINKER_FLAGS="${LD_LIB}" \
      -DCMAKE_SHARED_LINKER_FLAGS="${LD_LIB}"; \
    cmake --build /tmp/ngx_brotli/deps/brotli/out --parallel; \
    cmake --install /tmp/ngx_brotli/deps/brotli/out; \
    strip -s /usr/local/lib/libbrotli*.so* || true

# ---------------------------------------------------------
# 8) ngx_http_zstd_module
# ---------------------------------------------------------
RUN set -eux; \
    git clone --branch "${NGX_ZSTD_MODULE_VERSION}" --depth=1 \
      https://github.com/HanadaLee/ngx_http_zstd_module.git /tmp/ngx_http_zstd_module; \
    sed -i 's/-l:libzstd.a/-lzstd/g' /tmp/ngx_http_zstd_module/config

# ---------------------------------------------------------
# 9) NGINX
# ---------------------------------------------------------
RUN set -eux; \
    curl -fSLO "https://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz"; \
    curl -fSLO "https://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz.asc"; \
    mkdir -p /tmp/nginx-keys; \
    for key in nginx_signing mdounin arut pluknet sb thresh; do \
      curl -fsSL "https://nginx.org/keys/${key}.key" -o "/tmp/nginx-keys/${key}.key" || true; \
    done; \
    gpg --batch --import /tmp/nginx-keys/*.key; \
    gpg --batch --verify "nginx-${NGINX_VERSION}.tar.gz.asc" "nginx-${NGINX_VERSION}.tar.gz"; \
    tar -xzf "nginx-${NGINX_VERSION}.tar.gz"; \
    mv "nginx-${NGINX_VERSION}" /tmp/nginx; \
    cd /tmp/nginx; \
    test -f /usr/local/lib/libpcre2-8.a; \
    test -f /usr/local/lib/libjemalloc.so.2; \
    test -f /usr/local/include/pcre2.h; \
    test -f /usr/local/include/zlib.h; \
    test -f /opt/awslc/lib/libssl.so; \
    test -f /opt/awslc/lib/libcrypto.so; \
    export PKG_CONFIG_PATH="/usr/local/lib/pkgconfig:/usr/local/lib64/pkgconfig:/opt/awslc/lib/pkgconfig"; \
    LD_OPT="${LD_NGINX} ${LTO_FLAGS}"; \
    LD_OPT="${LD_OPT} -Wl,-rpath,/opt/awslc/lib:/usr/local/lib"; \
    LD_OPT="${LD_OPT} -L/opt/awslc/lib -L/usr/local/lib"; \
    LD_OPT="${LD_OPT} -Wl,--no-as-needed -ljemalloc -Wl,--as-needed"; \
    LD_OPT="${LD_OPT} -lssl -lcrypto -lpcre2-8 -lz -lzstd"; \
    LD_OPT="${LD_OPT} -lbrotlienc -lbrotlicommon"; \
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
      --with-http_ssl_module \
      --with-http_v2_module \
      --with-http_v3_module \
      --with-http_realip_module \
      --with-http_gzip_static_module \
      --without-http_fastcgi_module \
      --without-http_uwsgi_module \
      --without-http_scgi_module \
      --without-http_grpc_module \
      --without-http_memcached_module \
      --without-http_ssi_module \
      --without-http_userid_module \
      --without-http_auth_basic_module \
      --without-http_autoindex_module \
      --without-http_empty_gif_module \
      --without-http_browser_module \
      --without-http_referer_module \
      --without-http_geo_module \
      --without-http_split_clients_module \
      --without-http_mirror_module \
      --without-mail_pop3_module \
      --without-mail_imap_module \
      --without-mail_smtp_module \
      --without-poll_module \
      --without-select_module \
      --add-module=/tmp/ngx_brotli \
      --add-module=/tmp/ngx_http_zstd_module \
      --with-cc-opt="${CPU_FLAGS} ${LTO_FLAGS} -I/opt/awslc/include -I/usr/local/include" \
      --with-ld-opt="${LD_OPT}"; \
    make -j"$(nproc)"; \
    make install; \
    strip -s /usr/sbin/nginx; \
    if compgen -G "/usr/lib/nginx/modules/*.so" > /dev/null; then \
      strip -s /usr/lib/nginx/modules/*.so || true; \
    fi; \
    nginx -V 2>&1 | tee /tmp/nginx-build-version.txt; \
    grep -q -- '--with-http_v3_module' /tmp/nginx-build-version.txt; \
    grep -q -- '--with-http_v2_module' /tmp/nginx-build-version.txt; \
    grep -q -- '--with-pcre-jit' /tmp/nginx-build-version.txt; \
    grep -q -- '--with-http_realip_module' /tmp/nginx-build-version.txt; \
    grep -q -- '--with-http_gzip_static_module' /tmp/nginx-build-version.txt; \
    grep -q -- '--without-poll_module' /tmp/nginx-build-version.txt; \
    grep -q -- '--without-select_module' /tmp/nginx-build-version.txt; \
    grep -q -- '--without-http_auth_basic_module' /tmp/nginx-build-version.txt; \
    grep -q -- '--add-module=/tmp/ngx_brotli' /tmp/nginx-build-version.txt; \
    grep -q -- '--add-module=/tmp/ngx_http_zstd_module' /tmp/nginx-build-version.txt; \
    ! grep -q -- '--without-http_map_module' /tmp/nginx-build-version.txt; \
    ! grep -q -- '--with-threads' /tmp/nginx-build-version.txt; \
    ! grep -q -- '--with-file-aio' /tmp/nginx-build-version.txt; \
    ! grep -q -- '--with-stream' /tmp/nginx-build-version.txt; \
    ldd /usr/sbin/nginx | tee /tmp/builder_ldd.txt; \
    ! grep -q "not found" /tmp/builder_ldd.txt; \
    ! grep -qi "libpcre2" /tmp/builder_ldd.txt; \
    grep -qi "jemalloc" /tmp/builder_ldd.txt; \
    rm -rf \
      /tmp/nginx \
      "/tmp/nginx-${NGINX_VERSION}.tar.gz" \
      "/tmp/nginx-${NGINX_VERSION}.tar.gz.asc" \
      /tmp/nginx-keys \
      /root/.gnupg \
      /tmp/ngx_brotli \
      /tmp/ngx_http_zstd_module \
      /tmp/nginx-build-version.txt \
      /tmp/builder_ldd.txt

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
ARG JEMALLOC_MALLOC_CONF

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN set -eux; \
    apt-get update; \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      ca-certificates \
      wget; \
    rm -rf /var/lib/apt/lists/*

RUN set -eux; \
    if ! getent group nginx >/dev/null; then \
      groupadd --system --gid 101 nginx || groupadd --system nginx; \
    fi; \
    if ! id -u nginx >/dev/null 2>&1; then \
      useradd --system --uid 101 --gid nginx --no-log-init --shell /usr/sbin/nologin nginx \
      || useradd --system --gid nginx --no-log-init --shell /usr/sbin/nologin nginx; \
    fi

COPY --link --from=builder /usr/sbin/nginx              /usr/sbin/nginx
COPY --link --from=builder /etc/nginx                   /etc/nginx

COPY --link --from=builder /usr/local/lib/libjemalloc.so*   /usr/local/lib/
COPY --link --from=builder /usr/local/lib/libzstd.so*       /usr/local/lib/
COPY --link --from=builder /usr/local/lib/libbrotli*.so*    /usr/local/lib/

COPY --link --from=builder /usr/local/lib/libz.so.1.0.0     /usr/local/lib/
COPY --link --from=builder /usr/local/lib/libz.so.1         /usr/local/lib/
COPY --link --from=builder /usr/local/lib/libz.so           /usr/local/lib/

COPY --link --from=builder /opt/awslc/lib/libssl.so*        /opt/awslc/lib/
COPY --link --from=builder /opt/awslc/lib/libcrypto.so*     /opt/awslc/lib/

ENV MALLOC_CONF="${JEMALLOC_MALLOC_CONF}" \
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
      /etc/nginx/quic \
      /run; \
    chown -R nginx:nginx /etc/nginx /var/log/nginx /var/cache/nginx; \
    rm -rf /etc/nginx/logs; \
    ln -sf /var/log/nginx /etc/nginx/logs; \
    ln -sf /dev/stdout /var/log/nginx/access.log; \
    ln -sf /dev/stderr /var/log/nginx/error.log; \
    printf "/usr/local/lib\n/opt/awslc/lib\n" > /etc/ld.so.conf.d/jbs-custom-libs.conf; \
    ldconfig; \
    umask 077; \
    head -c 32 /dev/urandom > /etc/nginx/quic/host.key; \
    chmod 600 /etc/nginx/quic/host.key; \
    ldd /usr/sbin/nginx | tee /tmp/runtime_ldd.txt; \
    ! grep -q "not found" /tmp/runtime_ldd.txt; \
    ! grep -qi "libpcre2" /tmp/runtime_ldd.txt; \
    grep -qi "jemalloc" /tmp/runtime_ldd.txt; \
    nginx -V; \
    nginx -t; \
    nginx; \
    sleep 0.5; \
    NGINX_PID="$(cat /var/run/nginx.pid)"; \
    grep -qi jemalloc "/proc/${NGINX_PID}/maps" \
      && echo "[OK] jemalloc confirmed in running nginx master maps" \
      || { echo "[ERROR] jemalloc not found in running nginx master maps" >&2; nginx -s quit || true; exit 1; }; \
    nginx -s quit; \
    sleep 0.5; \
    rm -f /etc/nginx/quic/host.key /tmp/runtime_ldd.txt

RUN cat > /usr/local/bin/jbs-nginx-entrypoint <<'EOF'
#!/bin/sh
set -e

if [ "${1#-}" != "$1" ]; then
  set -- nginx "$@"
fi

if [ "$1" = "nginx" ]; then
  mkdir -p /etc/nginx/quic 2>/dev/null || true
  if [ -d /etc/nginx/quic ] && [ ! -s /etc/nginx/quic/host.key ]; then
    umask 077
    head -c 32 /dev/urandom > /etc/nginx/quic/host.key 2>/dev/null || true
    chmod 600 /etc/nginx/quic/host.key 2>/dev/null || true
  fi

  # Cloudflare real-ip 파일만 호환용으로 생성.
  touch /etc/nginx/cloudflare-ips.conf 2>/dev/null || true
fi

exec "$@"
EOF

RUN chmod +x /usr/local/bin/jbs-nginx-entrypoint

EXPOSE 80 443/tcp 443/udp

HEALTHCHECK --interval=60s --timeout=3s --start-period=15s --retries=3 \
  CMD wget -qO- --max-redirect=0 --timeout=2 http://127.0.0.1/nginx-health > /dev/null 2>&1 \
      || wget -qO- --max-redirect=0 --timeout=2 http://127.0.0.1/ > /dev/null 2>&1 \
      || exit 1

STOPSIGNAL SIGQUIT

LABEL project="JBS Networks NGINX 5.4 Synergy Lite v3" \
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
      memory.policy="zen1-1vcpu-1gb-jemalloc-direct-link-low-rss" \
      compatibility="keeps-map-realip-proxy-cache-limit-http2-http3-brotli-zstd-gzip-cloudflare-realip" \
      optimization="Zen1/Clang/LLD/ThinLTO/AWS-LC-5.1.0/Jemalloc-DirectLink/PCRE2-Static/zlib-rs-0.6.5/Brotli/Zstd/HTTP3/LowOverhead/EpollOnly/NoStream/NoThreads/NoAIO"

ENTRYPOINT ["/usr/local/bin/jbs-nginx-entrypoint"]
CMD ["nginx", "-g", "daemon off;"]
