ARG NGINX_VERSION=1.29.7
ARG CPU_FLAGS="-O3 -march=znver3 -mtune=znver3 -mavx2 -mfma -mbmi2 -madx -DNDEBUG -fPIC -fstack-protector-strong -D_FORTIFY_SOURCE=2"
ARG LTO_FLAGS="-flto=auto"

FROM debian:trixie-slim AS builder
ARG CPU_FLAGS
ARG LTO_FLAGS
ARG NGINX_VERSION

# ✅ AWS-LC 빌드에 필수적인 golang 복구 및 종속성 설치
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential cmake wget curl perl ca-certificates binutils \
    pkg-config git ninja-build golang \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /tmp

# 1. PCRE2 (JIT 최적화)
RUN wget -qO- https://github.com/PCRE2Project/pcre2/releases/download/pcre2-10.47/pcre2-10.47.tar.gz | tar -zxf - && \
    cd pcre2-10.47 && \
    CFLAGS="${CPU_FLAGS} ${LTO_FLAGS}" ./configure --prefix=/usr/local --enable-jit --enable-shared && \
    make -j$(nproc) && make install

# 2. AWS-LC (OpenSSL 대체, HTTP/3 최적화)
RUN git clone --branch v1.71.0 --depth=1 https://github.com/aws/aws-lc.git /tmp/aws-lc && \
    cd /tmp/aws-lc && \
    cmake -B build -GNinja -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=ON -DCMAKE_INSTALL_PREFIX=/opt/awslc \
    -DCMAKE_INSTALL_LIBDIR=lib -DCMAKE_C_FLAGS="${CPU_FLAGS} -fPIC" \
    -DCMAKE_CXX_FLAGS="${CPU_FLAGS} -fPIC" \
    -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=ON && \
    ninja -C build && ninja -C build install

# 3. Jemalloc (고성능 메모리 할당자)
RUN wget -qO- https://github.com/jemalloc/jemalloc/releases/download/5.3.0/jemalloc-5.3.0.tar.bz2 | tar -xjf - && \
    cd jemalloc-5.3.0 && \
    CFLAGS="${CPU_FLAGS} ${LTO_FLAGS}" ./configure --prefix=/usr/local --disable-cxx --enable-stats && \
    make -j$(nproc) && make install

# 4. zlib-ng (Gzip SIMD 최적화)
RUN git clone --branch 2.3.3 --depth=1 https://github.com/zlib-ng/zlib-ng.git && \
    cd zlib-ng && \
    cmake -B build -DCMAKE_C_FLAGS="${CPU_FLAGS} ${LTO_FLAGS}" \
    -DCMAKE_SHARED_LINKER_FLAGS="${LTO_FLAGS}" -DCMAKE_EXE_LINKER_FLAGS="${LTO_FLAGS}" \
    -DZLIB_COMPAT=ON -DCMAKE_INSTALL_PREFIX=/usr/local && \
    cmake --build build --config Release -j$(nproc) && \
    cmake --install build

# 5. Zstd
RUN wget -qO- https://github.com/facebook/zstd/releases/download/v1.5.7/zstd-1.5.7.tar.gz | tar -zxf - && \
    cd zstd-1.5.7 && \
    CFLAGS="${CPU_FLAGS} ${LTO_FLAGS}" LDFLAGS="${LTO_FLAGS}" make -j$(nproc) && \
    make install PREFIX=/usr/local

# 6. Brotli & Zstd NGINX 모듈 준비
RUN git clone --depth=1 --recurse-submodules https://github.com/google/ngx_brotli.git /tmp/ngx_brotli && \
    cd /tmp/ngx_brotli/deps/brotli && \
    cmake -DBUILD_SHARED_LIBS=ON -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_FLAGS="${CPU_FLAGS} ${LTO_FLAGS}" -DCMAKE_CXX_FLAGS="${CPU_FLAGS} ${LTO_FLAGS}" \
    -DCMAKE_INSTALL_PREFIX=/usr/local . && \
    make -j$(nproc) && make install && \
    git clone --depth=1 https://github.com/HanadaLee/ngx_http_zstd_module.git /tmp/ngx_http_zstd_module

# 7. NGINX 다운로드 및 정적 라이브러리 링크 수정
RUN curl -fSL "https://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz" | tar -zxf - && \
    mv "nginx-${NGINX_VERSION}" nginx

WORKDIR /tmp/nginx
RUN sed -i 's/-l:libzstd.a/-lzstd/g' /tmp/ngx_http_zstd_module/config

# 8. NGINX 컴파일 (추가하신 모듈 및 사용자 권한 명시 적용)
RUN export PKG_CONFIG_PATH=/usr/local/lib/pkgconfig && \
    ./configure --prefix=/etc/nginx \
    --sbin-path=/usr/sbin/nginx \
    --modules-path=/usr/lib/nginx/modules \
    --conf-path=/etc/nginx/nginx.conf \
    --error-log-path=/etc/nginx/logs/error.log \
    --http-log-path=/etc/nginx/logs/access.log \
    --pid-path=/var/run/nginx.pid \
    --user=nginx --group=nginx \
    --with-pcre-jit --with-threads --with-file-aio \
    --with-compat --with-http_v2_module \
    --with-http_v3_module --with-http_ssl_module \
    --with-http_realip_module --with-http_stub_status_module \
    --with-http_gzip_static_module --with-http_gunzip_module \
    --with-http_slice_module --with-stream \
    --with-stream_ssl_module --with-stream_realip_module \
    --with-stream_ssl_preread_module \
    --with-http_auth_request_module \
    --with-http_sub_module \
    --with-http_secure_link_module \
    --add-dynamic-module=/tmp/ngx_brotli \
    --add-dynamic-module=/tmp/ngx_http_zstd_module \
    --with-cc-opt="${CPU_FLAGS} ${LTO_FLAGS} -I/opt/awslc/include -I/usr/local/include" \
    --with-ld-opt="${LTO_FLAGS} -L/opt/awslc/lib -L/usr/local/lib -lssl -lcrypto -lpcre2-8 -lz -lzstd -lbrotlienc -lbrotlicommon -Wl,-rpath,/opt/awslc/lib:/usr/local/lib -Wl,--as-needed" && \
    make -j$(nproc) && make install && \
    strip -s /usr/sbin/nginx /usr/lib/nginx/modules/*.so && \
    ldd /usr/sbin/nginx | grep "not found" || true

# ✅ 모듈 로드 파일 분리 및 기본 NGINX 설정에 헬스체크용 라우팅 임시 주입
RUN printf '%s\n' \
      'load_module /usr/lib/nginx/modules/ngx_http_brotli_filter_module.so;' \
      'load_module /usr/lib/nginx/modules/ngx_http_brotli_static_module.so;' \
      'load_module /usr/lib/nginx/modules/ngx_http_zstd_filter_module.so;' \
      'load_module /usr/lib/nginx/modules/ngx_http_zstd_static_module.so;' \
      > /etc/nginx/modules-load.conf && \
    sed -i '1s|^|include /etc/nginx/modules-load.conf;\n|' /etc/nginx/nginx.conf && \
    sed -i '/server {/a \    location /nginx-health {\n        access_log off;\n        return 200 "healthy\\n";\n    }' /etc/nginx/nginx.conf

# --- 실행 환경(Runtime) 구성 ---
FROM debian:trixie-slim

# ✅ HEALTHCHECK용 curl 패키지 포함
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl \
    && rm -rf /var/lib/apt/lists/*

# ✅ nginx 사용자 생성 (nologin)
RUN groupadd -r nginx && useradd -r -g nginx -s /sbin/nologin nginx

COPY --from=builder /usr/sbin/nginx          /usr/sbin/nginx
COPY --from=builder /usr/lib/nginx/modules   /usr/lib/nginx/modules
COPY --from=builder /etc/nginx               /etc/nginx

COPY --from=builder /usr/local/lib/libpcre2-8.so* /usr/local/lib/
COPY --from=builder /usr/local/lib/libz.so* /usr/local/lib/
COPY --from=builder /usr/local/lib/libjemalloc.so* /usr/local/lib/
COPY --from=builder /usr/local/lib/libzstd.so* /usr/local/lib/
COPY --from=builder /usr/local/lib/libbrotli*.so* /usr/local/lib/
COPY --from=builder /opt/awslc/lib/libssl.so* /opt/awslc/lib/
COPY --from=builder /opt/awslc/lib/libcrypto.so* /opt/awslc/lib/

# 디렉토리 권한을 새로 생성한 nginx 유저에 맞춤
RUN mkdir -p /etc/nginx/logs && \
    chown -R nginx:nginx /etc/nginx && \
    ln -sf /dev/stdout /etc/nginx/logs/access.log && \
    ln -sf /dev/stderr /etc/nginx/logs/error.log && \
    printf "/usr/local/lib\n/opt/awslc/lib\n" > /etc/ld.so.conf.d/custom-libs.conf && \
    ldconfig && \
    nginx -t

# Jemalloc 튜닝 완료본 적용
ENV LD_PRELOAD="/usr/local/lib/libjemalloc.so.2" \
    MALLOC_CONF="background_thread:true,metadata_thp:auto,percpu_arena:percpu,tcache_max:32768,dirty_decay_ms:30000,muzzy_decay_ms:30000,stats_print:false"

EXPOSE 80 443/tcp 443/udp

# Graceful shutdown 지원
STOPSIGNAL SIGQUIT

# 헬스체크 추가
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD curl -fsS http://127.0.0.1/nginx-health || exit 1

LABEL project="JBS Networks 4.3" \
      optimization="Zen3/AWS-LC/Zstd/Brotli/zlib-ng/Jemalloc/PCRE2-JIT/Full-LTO/QUIC-HTTP3"

CMD ["nginx", "-g", "daemon off;"]
