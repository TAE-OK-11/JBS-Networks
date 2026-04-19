# syntax=docker/dockerfile:1.7

# =========================================================
# JBS Networks NGINX 4.8 - stabilized final
# 2026-04-19
# =========================================================

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
ARG NGX_BROTLI_REF=a71f931603a7e3905087349927d693ca6972046d

ARG CPU_FLAGS="-O3 -march=znver3 -mtune=znver3 -pipe -fstack-protector-strong -D_FORTIFY_SOURCE=3 -ffunction-sections -fdata-sections -fno-semantic-interposition -DNDEBUG"
ARG LTO_FLAGS="-flto=full"

# =========================================================
# Builder
# =========================================================
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
      --enable-shared; \
    make -j"$(nproc)"; \
    make install; \
    strip -s /usr/local/lib/libpcre2-8.so* || true

# ---------------------------------------------------------
# 2) AWS-LC
# ---------------------------------------------------------
RUN set -eux; \
    git clone --branch "${AWSLC_VERSION}" --depth=1 https://github.com/aws/aws-lc.git /tmp/aws-lc; \
    # CMAKE_INTERPROCEDURAL_OPTIMIZATION=ON 은 CMake가 -flto=thin 을 자동 추가해
    # CMAKE_C_FLAGS 의 -flto=full 과 충돌함. LTO 는 FLAGS에서 명시 제어하므로 IPO 제거.
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
      --disable-cxx; \
    make -j"$(nproc)"; \
    make install; \
    strip -s /usr/local/lib/libjemalloc.so* || true

# ---------------------------------------------------------
# 4) zlib-rs
# NOTE: cargo cinstall --libdir=/usr/local/lib 이 이미 /usr/local/lib 에
#       libz_rs.so(+ 버전 심볼릭 링크/헤더/pkgconfig)를 직접 설치함.
#       이 경로로 다시 `cp` 또는 `install`을 호출하면 GNU install의
#       "are the same file" 검사에 걸려 set -e 환경에서 exit 1 로 실패함.
#       따라서 재설치 단계 없이 실제 regular file만 탐지 → patchelf → symlink 로 처리함.
#       또한 일부 cargo-c 구성은 실제 파일을 libz_rs.so.X.Y.Z 로 두고
#       libz_rs.so 를 심볼릭 링크로 설치하므로 `-type f` 단독 탐색은 실패할 수 있음.
#       → `readlink -f` + 규칙 기반 fallback 으로 robust 하게 탐지.
# ---------------------------------------------------------
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
    export RUSTFLAGS="-C target-cpu=znver3 -C opt-level=3 -C codegen-units=1 -C llvm-args=-enable-dfa-jump-thread"; \
    cargo cinstall --release --prefix=/usr/local --libdir=/usr/local/lib; \
    # 헤더가 /usr/local/include/libz_rs/ 하위에 설치될 경우 canonical 경로에 복사 (이미 있으면 skip) \
    if [ -d /usr/local/include/libz_rs ]; then \
      [ -e /usr/local/include/zlib.h ]  || cp /usr/local/include/libz_rs/zlib.h  /usr/local/include/zlib.h; \
      [ -e /usr/local/include/zconf.h ] || cp /usr/local/include/libz_rs/zconf.h /usr/local/include/zconf.h || true; \
    fi; \
    # 실제 regular .so 파일 탐지 (심볼릭 링크면 readlink -f 로 실체 경로 획득) \
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
    # SONAME 을 libz.so.1 로 교정 → nginx ELF NEEDED 항목과 일치 \
    patchelf --set-soname libz.so.1 "/usr/local/lib/${REAL_SO}"; \
    # canonical 'libz_rs.so' 이름 보장 (runtime stage 의 COPY 구문이 이 이름을 기대함) \
    if [ ! -e /usr/local/lib/libz_rs.so ]; then \
      ln -sf "${REAL_SO}" /usr/local/lib/libz_rs.so; \
    fi; \
    # zlib 호환 심볼릭 링크 재생성 (기존 파일/링크 제거 후 생성 → set -e 충돌 방지) \
    rm -f /usr/local/lib/libz.so /usr/local/lib/libz.so.1; \
    ln -sf "${REAL_SO}" /usr/local/lib/libz.so.1; \
    ln -sf "${REAL_SO}" /usr/local/lib/libz.so; \
    strip --strip-debug "/usr/local/lib/${REAL_SO}" || true

# ---------------------------------------------------------
# 5) zstd
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
    strip -s /usr/local/lib/libzstd.so* || true

# ---------------------------------------------------------
# 6) Brotli + nginx zstd module
# NOTE: NGX_BROTLI_REF 는 브랜치/태그가 아닌 커밋 SHA 이므로
#       --depth=1 shallow clone 후 `git fetch <sha>` 는 GitHub 서버가
#       임의 SHA 직접 fetch 를 거부해 exit 128 로 실패함.
#       → --filter=blob:none (blobless partial clone) 사용:
#         커밋/트리 메타데이터는 전부 받고, 블롭은 checkout 시점에만 받아옴.
#         임의 SHA checkout 이 가능하면서 full clone 보다 빠름.
# ---------------------------------------------------------
RUN set -eux; \
    git clone --filter=blob:none \
      https://github.com/google/ngx_brotli.git /tmp/ngx_brotli; \
    cd /tmp/ngx_brotli; \
    git checkout "${NGX_BROTLI_REF}"; \
    git submodule update --init --recursive --filter=blob:none -j8; \
    # CMAKE_C_COMPILER=clang: 명시하지 않으면 CC env 가 무시되고 gcc 가 선택될 수 있음.
    # CMAKE_INSTALL_LIBDIR=lib: Debian 에서 GNUInstallDirs 가 기본값으로
    #   lib/x86_64-linux-gnu/ 를 사용하므로, 명시하지 않으면 libbrotli*.so 가
    #   /usr/local/lib/x86_64-linux-gnu/ 에 설치되어 뒤따르는 COPY 및
    #   nginx -L/usr/local/lib 에서 라이브러리를 찾지 못함.
    cmake -S /tmp/ngx_brotli/deps/brotli -B /tmp/ngx_brotli/deps/brotli/out -GNinja \
      -DCMAKE_BUILD_TYPE=Release \
      -DBUILD_SHARED_LIBS=ON \
      -DCMAKE_INSTALL_PREFIX=/usr/local \
      -DCMAKE_INSTALL_LIBDIR=lib \
      -DCMAKE_C_COMPILER=clang \
      -DCMAKE_C_FLAGS="${CPU_FLAGS} ${LTO_FLAGS}" \
      -DCMAKE_SHARED_LINKER_FLAGS="-fuse-ld=lld ${LTO_FLAGS} -Wl,--gc-sections"; \
    cmake --build /tmp/ngx_brotli/deps/brotli/out --parallel; \
    cmake --install /tmp/ngx_brotli/deps/brotli/out; \
    git clone --branch "${NGX_ZSTD_MODULE_VERSION}" --depth=1 \
      https://github.com/HanadaLee/ngx_http_zstd_module.git /tmp/ngx_http_zstd_module

# ---------------------------------------------------------
# 7) NGINX
# ---------------------------------------------------------
RUN set -eux; \
    curl -fSL "https://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz" \
      -o "nginx-${NGINX_VERSION}.tar.gz"; \
    echo "${NGINX_SHA256}  nginx-${NGINX_VERSION}.tar.gz" | sha256sum -c -; \
    tar -xzf "nginx-${NGINX_VERSION}.tar.gz"; \
    mv "nginx-${NGINX_VERSION}" /tmp/nginx; \
    cd /tmp/nginx; \
    sed -i 's/-l:libzstd.a/-lzstd/g' /tmp/ngx_http_zstd_module/config; \
    export PKG_CONFIG_PATH="/usr/local/lib/pkgconfig:/usr/local/lib64/pkgconfig:/opt/awslc/lib/pkgconfig"; \
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
      --with-ld-opt="-fuse-ld=lld ${LTO_FLAGS} -Wl,-O3 -Wl,--as-needed -Wl,--gc-sections -Wl,-rpath,/opt/awslc/lib:/usr/local/lib -L/opt/awslc/lib -L/usr/local/lib -lssl -lcrypto -lpcre2-8 -lz -lzstd -lbrotlienc -lbrotlicommon"; \
    make -j"$(nproc)"; \
    make install; \
    strip -s /usr/sbin/nginx; \
    if compgen -G "/usr/lib/nginx/modules/*.so" > /dev/null; then \
      strip -s /usr/lib/nginx/modules/*.so; \
    fi; \
    nginx -V 2>&1 | grep -q -- '--with-http_v3_module'; \
    ldd /usr/sbin/nginx | tee /tmp/builder_ldd.txt; \
    ! grep -q "not found" /tmp/builder_ldd.txt

# =========================================================
# Runtime
# =========================================================
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
    curl \
    && rm -rf /var/lib/apt/lists/*

RUN groupadd -r nginx && useradd -r -g nginx -s /usr/sbin/nologin nginx

COPY --from=builder /usr/sbin/nginx /usr/sbin/nginx
COPY --from=builder /etc/nginx /etc/nginx

COPY --from=builder /usr/local/lib/libpcre2-8.so* /usr/local/lib/
COPY --from=builder /usr/local/lib/libjemalloc.so* /usr/local/lib/
COPY --from=builder /usr/local/lib/libzstd.so* /usr/local/lib/
COPY --from=builder /usr/local/lib/libbrotli*.so* /usr/local/lib/
COPY --from=builder /usr/local/lib/libz_rs.so /usr/local/lib/
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
    # /etc/nginx/logs → /var/log/nginx 심볼릭 링크
    # rm -rf 선행으로 "디렉터리 내부에 링크 생성" 문제 방지
    rm -rf /etc/nginx/logs; \
    ln -sf /var/log/nginx /etc/nginx/logs; \
    ln -sf /dev/stdout /var/log/nginx/access.log; \
    ln -sf /dev/stderr /var/log/nginx/error.log; \
    printf "/usr/local/lib\n/opt/awslc/lib\n" > /etc/ld.so.conf.d/custom-libs.conf; \
    # COPY는 심볼릭 링크를 follow하므로 libz_rs.so 실체만 복사됨.
    # libz 호환 심볼릭 링크를 runtime에서 재생성
    ln -sf libz_rs.so /usr/local/lib/libz.so.1; \
    ln -sf libz_rs.so /usr/local/lib/libz.so; \
    ldconfig; \
    ldd /usr/sbin/nginx | tee /tmp/ldd.txt; \
    ! grep -q "not found" /tmp/ldd.txt; \
    nginx -V; \
    LD_PRELOAD=/usr/local/lib/libjemalloc.so.2 nginx -t

ENV LD_PRELOAD="/usr/local/lib/libjemalloc.so.2" \
    MALLOC_CONF="background_thread:true,metadata_thp:auto,percpu_arena:phycpu,tcache_max:32768,dirty_decay_ms:30000,muzzy_decay_ms:30000"

EXPOSE 80 443/tcp 443/udp

# HTTP healthcheck: nginx가 127.0.0.1:80에서 HTTP를 서비스한다고 가정.
# stream-only/TCP-only 배포 시 적합한 probe로 교체 필요.
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD curl -fs http://127.0.0.1/ || exit 1

STOPSIGNAL SIGQUIT

LABEL project="JBS Networks 4.8 Rust-Optimized" \
      nginx.version="${NGINX_VERSION}" \
      awslc.version="${AWSLC_VERSION}" \
      zlib-rs.version="${ZLIBRS_VERSION}" \
      cargo-c.version="${CARGOC_VERSION}" \
      zstd.version="${ZSTD_VERSION}" \
      jemalloc.version="${JEMALLOC_VERSION}" \
      ngx_brotli.ref="${NGX_BROTLI_REF}" \
      optimization="Extreme/Znver3/Full-LTO/Clang/LLD/AWS-LC/Jemalloc/zlib-rs/Brotli/Zstd"

CMD ["nginx", "-g", "daemon off;"]
