ARG NGINX_VERSION=1.29.7
ARG CPU_FLAGS="-O3 -march=znver3 -mtune=znver3 -mavx2 -mfma -mbmi2 -madx -DNDEBUG -fPIC"
ARG LTO_FLAGS="-flto=auto -ffat-lto-objects"

FROM debian:trixie-slim AS builder
ARG CPU_FLAGS
ARG LTO_FLAGS
ARG NGINX_VERSION

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential cmake wget curl perl ca-certificates binutils \
    pkg-config git golang ninja-build rustc cargo \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /tmp

RUN wget -qO- https://github.com/PCRE2Project/pcre2/releases/download/pcre2-10.47/pcre2-10.47.tar.gz | tar -zxf - && \
    cd pcre2-10.47 && \
    CFLAGS="${CPU_FLAGS} ${LTO_FLAGS}" ./configure --prefix=/usr/local --enable-jit --enable-shared && \
    make -j$(nproc) && make install

RUN git clone --branch v1.71.0 --depth=1 https://github.com/aws/aws-lc.git /tmp/aws-lc && \
    cd /tmp/aws-lc && \
    cmake -B build -GNinja -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=ON -DCMAKE_INSTALL_PREFIX=/opt/awslc \
    -DCMAKE_INSTALL_LIBDIR=lib -DCMAKE_C_FLAGS="${CPU_FLAGS} -fPIC" \
    -DCMAKE_CXX_FLAGS="${CPU_FLAGS} -fPIC" \
    -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=ON && \
    ninja -C build && ninja -C build install

RUN wget -qO- https://github.com/jemalloc/jemalloc/releases/download/5.3.0/jemalloc-5.3.0.tar.bz2 | tar -xjf - && \
    cd jemalloc-5.3.0 && \
    CFLAGS="${CPU_FLAGS} ${LTO_FLAGS}" ./configure --prefix=/usr/local --disable-cxx --enable-stats && \
    make -j$(nproc) && make install

RUN git clone --branch 2.3.3 --depth=1 https://github.com/zlib-ng/zlib-ng.git && \
    cd zlib-ng && \
    cmake -B build -DCMAKE_C_FLAGS="${CPU_FLAGS} ${LTO_FLAGS}" \
    -DCMAKE_SHARED_LINKER_FLAGS="${LTO_FLAGS}" -DCMAKE_EXE_LINKER_FLAGS="${LTO_FLAGS}" \
    -DZLIB_COMPAT=ON -DCMAKE_INSTALL_PREFIX=/usr/local && \
    cmake --build build --config Release -j$(nproc) && \
    cmake --install build

RUN wget -qO- https://github.com/facebook/zstd/releases/download/v1.5.7/zstd-1.5.7.tar.gz | tar -zxf - && \
    cd zstd-1.5.7 && \
    CFLAGS="${CPU_FLAGS} ${LTO_FLAGS}" LDFLAGS="${LTO_FLAGS}" make -j$(nproc) && \
    make install PREFIX=/usr/local

RUN git clone --depth=1 --recurse-submodules https://github.com/google/ngx_brotli.git && \
    cd /tmp/ngx_brotli/deps/brotli && \
    cmake -DBUILD_SHARED_LIBS=ON -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_FLAGS="${CPU_FLAGS} ${LTO_FLAGS}" -DCMAKE_CXX_FLAGS="${CPU_FLAGS} ${LTO_FLAGS}" \
    -DCMAKE_INSTALL_PREFIX=/usr/local . && \
    make -j$(nproc) && make install && \
    cd /tmp && git clone --depth=1 https://github.com/HanadaLee/ngx_http_zstd_module.git

RUN curl -fSL "https://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz" | tar -zxf - && \
    mv "nginx-${NGINX_VERSION}" nginx

WORKDIR /tmp/nginx
RUN sed -i 's/-l:libzstd.a/-lzstd/g' /tmp/ngx_http_zstd_module/config

RUN export PKG_CONFIG_PATH=/usr/local/lib/pkgconfig && \
    ./configure --prefix=/etc/nginx \
    --sbin-path=/usr/sbin/nginx \
    --modules-path=/usr/lib/nginx/modules \
    --conf-path=/etc/nginx/nginx.conf \
    --error-log-path=/etc/nginx/logs/error.log \
    --http-log-path=/etc/nginx/logs/access.log \
    --pid-path=/var/run/nginx.pid \
    --with-pcre-jit --with-threads --with-file-aio \
    --with-compat --with-http_v2_module \
    --with-http_v3_module --with-http_ssl_module \
    --with-http_realip_module --with-http_stub_status_module \
    --with-http_gzip_static_module --with-http_gunzip_module \
    --with-http_slice_module --with-stream \
    --with-stream_ssl_module --with-stream_realip_module \
    --add-dynamic-module=/tmp/ngx_brotli \
    --add-dynamic-module=/tmp/ngx_http_zstd_module \
    --with-cc-opt="${CPU_FLAGS} ${LTO_FLAGS} -I/opt/awslc/include -I/usr/local/include" \
    --with-ld-opt="${LTO_FLAGS} -L/opt/awslc/lib -L/usr/local/lib -lssl -lcrypto -lpcre2-8 -lz -lzstd -lbrotlienc -lbrotlicommon -Wl,-rpath,/opt/awslc/lib:/usr/local/lib -Wl,--as-needed" && \
    make -j$(nproc) && make install && \
    strip -s /usr/sbin/nginx /usr/lib/nginx/modules/*.so

RUN echo 'load_module /usr/lib/nginx/modules/ngx_http_brotli_filter_module.so;' > /etc/nginx/nginx.conf.new && \
    echo 'load_module /usr/lib/nginx/modules/ngx_http_brotli_static_module.so;' >> /etc/nginx/nginx.conf.new && \
    echo 'load_module /usr/lib/nginx/modules/ngx_http_zstd_filter_module.so;' >> /etc/nginx/nginx.conf.new && \
    echo 'load_module /usr/lib/nginx/modules/ngx_http_zstd_static_module.so;' >> /etc/nginx/nginx.conf.new && \
    cat /etc/nginx/nginx.conf >> /etc/nginx/nginx.conf.new && \
    mv /etc/nginx/nginx.conf.new /etc/nginx/nginx.conf

FROM debian:trixie-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates && \
    rm -rf /var/lib/apt/lists/*

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

RUN mkdir -p /etc/nginx/logs && \
    ln -sf /dev/stdout /etc/nginx/logs/access.log && \
    ln -sf /dev/stderr /etc/nginx/logs/error.log && \
    printf "/usr/local/lib\n/opt/awslc/lib\n" > /etc/ld.so.conf.d/custom-libs.conf && \
    ldconfig

# 요청하신 jemalloc LD_PRELOAD 및 MALLOC_CONF 설정 적용
ENV LD_PRELOAD="/usr/local/lib/libjemalloc.so.2" \
    MALLOC_CONF="background_thread:true,metadata_thp:auto,percpu_arena:percpu,tcache_max:65536,dirty_decay_ms:30000,muzzy_decay_ms:30000,stats_print:false"

EXPOSE 80 443/tcp 443/udp

LABEL project="JBS Networks 4.3" \
      optimization="Zen3/AWS-LC/Zstd/Brotli/zlib-ng/Jemalloc/PCRE2-JIT/Full-LTO/QUIC-HTTP3"

CMD ["nginx", "-g", "daemon off;"]
