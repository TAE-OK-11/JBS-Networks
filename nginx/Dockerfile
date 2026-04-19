# syntax=docker/dockerfile:1.7

# This Dockerfile is based on the optimized JBS Networks NGINX 4.8 build.
# It retains the key dependencies requested by the user (AWS‑LC, jemalloc,
# nginx 1.30.0 and zlib‑rs) while addressing a configure‑time failure
# triggered by nginx’s detection of the zlib library.  The upstream build
# attempted to replace the C implementation of zlib with a Rust
# implementation (zlib‑rs), but nginx’s configure script could not find
# the library when checking for `deflate` support.  To resolve this we
# ensure the Rust‑based library is visible to the compiler during
# configure by exporting appropriate CFLAGS and LDFLAGS, running
# ldconfig after installation and adjusting the linker search path.  See
# the build stage labelled “NGINX” for details.

ARG NGINX_VERSION=1.30.0
ARG NGINX_SHA256=058188c64bf22baecaa72b809a6318a4f9ba623889c554feab03f7cb853ab31b

ARG PCRE2_VERSION=10.47
ARG PCRE2_SHA256=c08ae2388ef333e8403e670ad70c0a11f1eed021fd88308d7e02f596fcd9dc16

ARG AWSLC_VERSION=v1.72.0

ARG JEMALLOC_VERSION=5.3.1
ARG JEMALLOC_SHA256=3826bc80232f22ed5c4662f3034f799ca316e819103bdc7bb99018a421706f92

ARG ZLIBRS_VERSION=v0.6.3
ARG CARGOC_VERSION=v0.10.7

ARG ZSTD_VERSION=1.5.7
ARG ZSTD_SHA256=eb33e51f49a15e023950cd7825ca74a4a2b43db8354825ac24fc1b7ee09e6fa3

ARG NGX_ZSTD_MODULE_VERSION=0.1.1
ARG NGX_BROTLI_REF=a71f9312c2deb28875acc7bacfdd5695a111aa53

# Compiler optimisation flags for Zen 3 class CPUs.  Feel free to
# override these at build time via `--build-arg CPU_FLAGS=...` if
# targeting another micro‑architecture.
ARG CPU_FLAGS="-O3 -march=znver3 -mtune=znver3 -pipe -fstack-protector-strong -D_FORTIFY_SOURCE=3 -ffunction-sections -fdata-sections -fno-semantic-interposition -DNDEBUG"
ARG LTO_FLAGS="-flto=full"

FROM debian:trixie-slim AS builder

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
    LD=ld.lld

# Validate architecture.  This image is tuned for x86‑64/znver3; fail
# early if another architecture is requested.
RUN case "${TARGETARCH:-amd64}" in \
      amd64|"") echo "Building for amd64/znver3";; \
      *) echo "Unsupported TARGETARCH=${TARGETARCH}. This image is x86_64/znver3 only." >&2; exit 1;; \
    esac

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

# ---------------------------------------------------------------------------
# 1) PCRE2
# ---------------------------------------------------------------------------
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

# ---------------------------------------------------------------------------
# 2) AWS‑LC
# ---------------------------------------------------------------------------
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
    strip -s /opt/awslc/lib/libssl.so* /opt/awslc/lib/libcrypto.so* || true

# ---------------------------------------------------------------------------
# 3) jemalloc
# ---------------------------------------------------------------------------
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

# ---------------------------------------------------------------------------
# 4) zlib‑rs
# ---------------------------------------------------------------------------
#
# The Rust‑based zlib implementation (`zlib‑rs`) is built and installed via
# cargo‑c.  After installation we run ldconfig so that libz.so can be
# discovered by the linker.  We also expose the headers in the usual
# include path.  Without these steps nginx’s configure test will fail
# with “zlib library … not found”.
RUN set -eux; \
    git clone --branch "${ZLIBRS_VERSION}" --depth=1 \
      https://github.com/trifectatechfoundation/zlib-rs.git /tmp/zlib-rs; \
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
    cd /tmp/zlib-rs/libz-rs-sys-cdylib; \
    export RUSTFLAGS="-C target-cpu=znver3 -C opt-level=3 -C codegen-units=1"; \
    # build and install the shared and static libraries
    cargo cinstall --release --prefix=/usr/local --libdir=/usr/local/lib; \
    # copy headers into the standard include location for C projects
    if [ -d /usr/local/include/libz_rs ]; then \
      [ -e /usr/local/include/zlib.h ]  || cp /usr/local/include/libz_rs/zlib.h  /usr/local/include/zlib.h; \
      [ -e /usr/local/include/zconf.h ] || cp /usr/local/include/libz_rs/zconf.h /usr/local/include/zconf.h; \
    fi; \
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
    # ensure the linker cache is up to date so -lz resolves libz-rs
    ldconfig; \
    # strip debug symbols
    strip --strip-debug /usr/local/lib/libz.so.1.0.0 || true

# ---------------------------------------------------------------------------
# 5) zstd
# ---------------------------------------------------------------------------
RUN set -eux; \
    wget -qO "zstd-${ZSTD_VERSION}.tar.gz" \
      "https://github.com/facebook/zstd/releases/download/v${ZSTD_VERSION}/zstd-${ZSTD_VERSION}.tar.gz"; \
    echo "${ZSTD_SHA256}  zstd-${ZSTD_VERSION}.tar.gz" | sha256sum -c -; \
    tar -xzf "zstd-${ZSTD_VERSION}.tar.gz"; \
    cd "zstd-${ZSTD_VERSION}"; \
    CFLAGS="${CPU_FLAGS} ${LTO_FLAGS}" \
    LDFLAGS="-fuse-ld=lld ${LTO_FLAGS} -Wl,--gc-sections" \
    make -j"$(nproc)" install PREFIX=/usr/local; \
    strip -s /usr/local/lib/libzstd.so* || true

# ---------------------------------------------------------------------------
# 6) Brotli & nginx zstd module
# ---------------------------------------------------------------------------
RUN set -eux; \
    git clone --filter=blob:none \
      https://github.com/google/ngx_brotli.git /tmp/ngx_brotli; \
    cd /tmp/ngx_brotli; \
    git checkout "${NGX_BROTLI_REF}"

RUN set -eux; \
    cd /tmp/ngx_brotli; \
    git submodule update --init --recursive --filter=blob:none

# Build Brotli as a shared library.  Do not specify --target brotlienc
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
    strip -s /usr/local/lib/libbrotli*.so* || true

RUN set -eux; \
    git clone --branch "${NGX_ZSTD_MODULE_VERSION}" --depth=1 \
      https://github.com/HanadaLee/ngx_http_zstd_module.git /tmp/ngx_http_zstd_module

# ---------------------------------------------------------------------------
# 7) NGINX
# ---------------------------------------------------------------------------
#
# During the nginx configure step the build system attempts to detect
# whether libz is available by compiling a small program that calls
# deflate() and links with -lz.  When using the Rust implementation
# this detection can fail unless the compiler is explicitly told
# where to find zlib.h and libz.so.  To fix this we set CFLAGS and
# LDFLAGS to include /usr/local/include and /usr/local/lib ahead of
# invoking ./configure.  Without these environment variables the
# configure script may report “the HTTP gzip module requires the zlib
# library” and abort.
RUN set -eux; \
    curl -fSL "https://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz" \
      -o "nginx-${NGINX_VERSION}.tar.gz"; \
    echo "${NGINX_SHA256}  nginx-${NGINX_VERSION}.tar.gz" | sha256sum -c -; \
    tar -xzf "nginx-${NGINX_VERSION}.tar.gz"; \
    mv "nginx-${NGINX_VERSION}" /tmp/nginx; \
    cd /tmp/nginx; \
    # fix zstd module config to use dynamic library
    sed -i 's/-l:libzstd.a/-lzstd/g' /tmp/ngx_http_zstd_module/config; \
    export PKG_CONFIG_PATH="/usr/local/lib/pkgconfig:/usr/local/lib64/pkgconfig:/opt/awslc/lib/pkgconfig"; \
    # set CFLAGS/LDFLAGS so that the zlib-rs headers and library are picked up
    export CFLAGS="${CPU_FLAGS} ${LTO_FLAGS} -I/opt/awslc/include -I/usr/local/include"; \
    export LDFLAGS="-L/opt/awslc/lib -L/usr/local/lib -fuse-ld=lld ${LTO_FLAGS} -Wl,-O3 -Wl,--as-needed -Wl,--gc-sections -Wl,-rpath,/opt/awslc/lib:/usr/local/lib"; \
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
      # pass our optimisation flags and include paths
      --with-cc-opt="${CPU_FLAGS} ${LTO_FLAGS} -I/opt/awslc/include -I/usr/local/include" \
      --with-ld-opt="-fuse-ld=lld ${LTO_FLAGS} -Wl,-O3 -Wl,--as-needed -Wl,--gc-sections -Wl,-rpath,/opt/awslc/lib:/usr/local/lib -L/opt/awslc/lib -L/usr/local/lib -lssl -lcrypto -lpcre2-8 -lz -lzstd -lbrotlienc -lbrotlicommon"; \
    make -j"$(nproc)"; \
    make install; \
    strip -s /usr/sbin/nginx; \
    if compgen -G "/usr/lib/nginx/modules/*.so" > /dev/null; then \
      strip -s /usr/lib/nginx/modules/*.so; \
    fi; \
    # verify HTTP/3 support and ensure all libraries are found
    nginx -V 2>&1 | grep -q -- '--with-http_v3_module'; \
    ldd /usr/sbin/nginx | tee /tmp/builder_ldd.txt; \
    ! grep -q "not found" /tmp/builder_ldd.txt

# ---------------------------------------------------------------------------
# Runtime stage
# ---------------------------------------------------------------------------
FROM debian:trixie-slim AS runtime

ARG NGINX_VERSION
ARG AWSLC_VERSION
ARG ZLIBRS_VERSION
ARG CARGOC_VERSION
ARG ZSTD_VERSION
ARG NGX_BROTLI_REF
ARG JEMALLOC_VERSION

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN groupadd -r nginx && useradd -r -g nginx -s /usr/sbin/nologin nginx

COPY --from=builder /usr/sbin/nginx /usr/sbin/nginx
COPY --from=builder /etc/nginx /etc/nginx

COPY --from=builder /usr/local/lib/libpcre2-8.so* /usr/local/lib/
COPY --from=builder /usr/local/lib/libjemalloc.so* /usr/local/lib/
COPY --from=builder /usr/local/lib/libzstd.so* /usr/local/lib/
COPY --from=builder /usr/local/lib/libbrotli*.so* /usr/local/lib/
COPY --from=builder /usr/local/lib/libz.so.1.0.0 /usr/local/lib/
COPY --from=builder /opt/awslc/lib/libssl.so* /opt/awslc/lib/
COPY --from=builder /opt/awslc/lib/libcrypto.so* /opt/awslc/lib/

RUN set -eux; \
    mkdir -p \
      /var/log/nginx \
      /var/cache/nginx/client_temp \
      /var/cache/nginx/proxy_temp \
      /var/cache/nginx/fastcgi_temp \
      /var/cache/nginx/uwsgi_temp \
      /var/cache/nginx/scgi_temp \
      /run; \
    chown -R nginx:nginx /etc/nginx /var/log/nginx /var/cache/nginx; \
    rm -rf /etc/nginx/logs; \
    ln -sf /var/log/nginx /etc/nginx/logs; \
    ln -sf /dev/stdout /var/log/nginx/access.log; \
    ln -sf /dev/stderr /var/log/nginx/error.log; \
    # ensure libz.so symlinks exist in runtime image
    ln -sf libz.so.1.0.0 /usr/local/lib/libz.so.1; \
    ln -sf libz.so.1.0.0 /usr/local/lib/libz.so; \
    printf "/usr/local/lib\n/opt/awslc/lib\n" > /etc/ld.so.conf.d/custom-libs.conf; \
    ldconfig; \
    ldd /usr/sbin/nginx | tee /tmp/ldd.txt; \
    ! grep -q "not found" /tmp/ldd.txt; \
    nginx -V; \
    LD_PRELOAD=/usr/local/lib/libjemalloc.so.2 nginx -t

ENV LD_PRELOAD="/usr/local/lib/libjemalloc.so.2" \
    MALLOC_CONF="background_thread:true,metadata_thp:auto,percpu_arena:phycpu,tcache_max:32768,dirty_decay_ms:30000,muzzy_decay_ms:30000"

EXPOSE 80 443/tcp 443/udp

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD nginx -t -q || exit 1

STOPSIGNAL SIGQUIT

LABEL project="JBS Networks 4.8 Rust‑Optimized" \
      nginx.version="${NGINX_VERSION}" \
      awslc.version="${AWSLC_VERSION}" \
      zlib-rs.version="${ZLIBRS_VERSION}" \
      cargo-c.version="${CARGOC_VERSION}" \
      zstd.version="${ZSTD_VERSION}" \
      jemalloc.version="${JEMALLOC_VERSION}" \
      ngx_brotli.ref="${NGX_BROTLI_REF}" \
      optimization="Extreme/Znver3/Full-LTO/Clang/LLD/AWS-LC/Jemalloc/zlib-rs/Brotli/Zstd"

CMD ["nginx", "-g", "daemon off;"]
