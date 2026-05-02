# syntax=docker/dockerfile:1.10

# JBS Networks — Jellyfin optimized runtime
# - Debian trixie-slim digest pinning
# - custom jemalloc + custom FFmpeg (Clang/LLD + Zen3 + ThinLTO)
# - Jellyfin runtime uses official portable server archive for maintainability

ARG DEBIAN_TRIXIE_DIGEST="sha256:4ffb3a1511099754cddc70eb1b12e50ffdb67619aa0ab6c13fcd800a78ef7c7a"
ARG JELLYFIN_VERSION="10.10.7"
ARG JEMALLOC_VERSION="5.3.1"
ARG JEMALLOC_SHA256="3826bc80232f22ed5c4662f3034f799ca316e819103bdc7bb99018a421706f92"
ARG FFMPEG_VERSION="8.1"
ARG FFMPEG_SHA256="c07039598df7d64d3c8b42c4e25b1959fc908621c6f6c2946881133f3b27eda2"
ARG CPU_FLAGS="-O3 -march=znver3 -mtune=znver3 -DNDEBUG -ffunction-sections -fdata-sections -pipe -fno-semantic-interposition"
ARG LTO_FLAGS="-flto=thin"

FROM debian:trixie-slim@${DEBIAN_TRIXIE_DIGEST} AS jellyfin-fetch
ARG JELLYFIN_VERSION
RUN --mount=type=cache,target=/var/cache/apt \
    apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl && \
    rm -rf /var/lib/apt/lists/*
WORKDIR /tmp
# Jellyfin 공식 수동 설치 경로를 사용하고, SHA256SUMS 기반으로 tarball 무결성 검증
RUN set -eux; \
    curl -fsSLO "https://repo.jellyfin.org/files/server/linux/stable/amd64/jellyfin_${JELLYFIN_VERSION}-amd64.tar.gz"; \
    curl -fsSLO "https://repo.jellyfin.org/files/server/linux/stable/amd64/sha256sum.txt"; \
    grep "jellyfin_${JELLYFIN_VERSION}-amd64.tar.gz" sha256sum.txt > jellyfin.sha256; \
    sha256sum -c jellyfin.sha256; \
    mkdir -p /out/jellyfin; \
    tar -xzf "jellyfin_${JELLYFIN_VERSION}-amd64.tar.gz" -C /out/jellyfin --strip-components=1

FROM debian:trixie-slim@${DEBIAN_TRIXIE_DIGEST} AS jemalloc-builder
ARG JEMALLOC_VERSION
ARG JEMALLOC_SHA256
ARG CPU_FLAGS
ARG LTO_FLAGS
RUN --mount=type=cache,target=/var/cache/apt \
    apt-get update && apt-get install -y --no-install-recommends \
      autoconf automake bzip2 build-essential ca-certificates clang libtool lld llvm wget && \
    rm -rf /var/lib/apt/lists/*
WORKDIR /build
RUN set -eux; \
    wget -qO jemalloc.tar.bz2 "https://github.com/jemalloc/jemalloc/releases/download/${JEMALLOC_VERSION}/jemalloc-${JEMALLOC_VERSION}.tar.bz2"; \
    echo "${JEMALLOC_SHA256}  jemalloc.tar.bz2" | sha256sum -c -; \
    tar -xjf jemalloc.tar.bz2; \
    cd "jemalloc-${JEMALLOC_VERSION}"; \
    CC=clang CXX=clang++ \
    CFLAGS="${CPU_FLAGS} ${LTO_FLAGS}" \
    CXXFLAGS="${CPU_FLAGS} ${LTO_FLAGS}" \
    LDFLAGS="${LTO_FLAGS} -fuse-ld=lld -Wl,--gc-sections -Wl,--as-needed -Wl,-z,relro,-z,now,-z,noexecstack" \
    ./configure --prefix=/usr/local --disable-cxx --disable-stats --enable-readlinkat; \
    make -j"$(nproc)"; \
    make install; \
    strip --strip-unneeded /usr/local/lib/libjemalloc.so.* || true

FROM debian:trixie-slim@${DEBIAN_TRIXIE_DIGEST} AS ffmpeg-builder
ARG FFMPEG_VERSION
ARG FFMPEG_SHA256
ARG CPU_FLAGS
ARG LTO_FLAGS
RUN --mount=type=cache,target=/var/cache/apt \
    apt-get update && apt-get install -y --no-install-recommends \
      build-essential ca-certificates clang lld llvm nasm yasm pkg-config wget \
      libass-dev libfreetype6-dev libfribidi-dev libgnutls28-dev libmp3lame-dev \
      libopus-dev libvorbis-dev libvpx-dev libx264-dev libx265-dev libzimg-dev libdav1d-dev \
      zlib1g-dev && \
    rm -rf /var/lib/apt/lists/*
WORKDIR /build
# Jellyfin 호환성을 위해 --disable-everything은 사용하지 않고, 필요한 코덱/필터를 넓게 유지
RUN set -eux; \
    wget -qO ffmpeg.tar.bz2 "https://ffmpeg.org/releases/ffmpeg-${FFMPEG_VERSION}.tar.bz2"; \
    echo "${FFMPEG_SHA256}  ffmpeg.tar.bz2" | sha256sum -c -; \
    tar -xjf ffmpeg.tar.bz2; \
    cd "ffmpeg-${FFMPEG_VERSION}"; \
    ./configure \
      --prefix=/usr/local \
      --cc=clang --cxx=clang++ \
      --arch=x86_64 --cpu=znver3 \
      --enable-gpl \
      --enable-version3 \
      --enable-shared \
      --disable-static \
      --disable-debug \
      --disable-doc \
      --enable-ffmpeg \
      --enable-ffprobe \
      --disable-ffplay \
      --enable-gnutls \
      --enable-libass \
      --enable-libdav1d \
      --enable-libfreetype \
      --enable-libfribidi \
      --enable-libmp3lame \
      --enable-libopus \
      --enable-libvorbis \
      --enable-libvpx \
      --enable-libx264 \
      --enable-libx265 \
      --enable-libzimg \
      --extra-cflags="${CPU_FLAGS} ${LTO_FLAGS}" \
      --extra-cxxflags="${CPU_FLAGS} ${LTO_FLAGS}" \
      --extra-ldflags="${LTO_FLAGS} -fuse-ld=lld -Wl,--gc-sections -Wl,--as-needed -Wl,-z,relro,-z,now,-z,noexecstack"; \
    make -j"$(nproc)"; \
    make install; \
    strip --strip-unneeded /usr/local/bin/ffmpeg /usr/local/bin/ffprobe || true; \
    strip --strip-unneeded /usr/local/lib/libav*.so* /usr/local/lib/libsw*.so* /usr/local/lib/libpostproc.so* || true

FROM debian:trixie-slim@${DEBIAN_TRIXIE_DIGEST} AS runtime
ARG JELLYFIN_VERSION
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN --mount=type=cache,target=/var/cache/apt \
    DEBIAN_FRONTEND=noninteractive apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl libfontconfig1 libfreetype6 libgcc-s1 libicu76 libssl3 libstdc++6 \
      libx11-6 libxml2 sqlite3 tzdata zlib1g && \
    rm -rf /var/lib/apt/lists/*

COPY --link --from=jellyfin-fetch /out/jellyfin /opt/jellyfin
COPY --link --from=ffmpeg-builder /usr/local /usr/local
COPY --link --from=jemalloc-builder /usr/local/lib/libjemalloc.so* /usr/local/lib/

RUN set -eux; \
    groupadd -g 1000 jellyfin; \
    useradd -u 1000 -g 1000 -d /config -s /usr/sbin/nologin jellyfin; \
    mkdir -p /config /cache /media /opt/jellyfin/data /opt/jellyfin/log; \
    chown -R jellyfin:jellyfin /config /cache /media /opt/jellyfin; \
    printf '/usr/local/lib\n' > /etc/ld.so.conf.d/local.conf; \
    ldconfig; \
    ln -sf /usr/local/bin/ffmpeg /usr/bin/ffmpeg; \
    ln -sf /usr/local/bin/ffprobe /usr/bin/ffprobe; \
    /usr/local/bin/ffmpeg -version >/dev/null; \
    /usr/local/bin/ffprobe -version >/dev/null; \
    /opt/jellyfin/jellyfin --version

ENV TZ="Asia/Seoul" \
    JELLYFIN_DATA_DIR="/config" \
    JELLYFIN_CACHE_DIR="/cache" \
    LD_PRELOAD="/usr/local/lib/libjemalloc.so.2" \
    MALLOC_CONF="background_thread:true,metadata_thp:auto,percpu_arena:phycpu,dirty_decay_ms:30000,muzzy_decay_ms:30000" \
    PATH="/usr/local/bin:${PATH}"

WORKDIR /opt/jellyfin
USER jellyfin:jellyfin
VOLUME ["/config", "/cache", "/media"]
EXPOSE 8096

HEALTHCHECK --interval=30s --timeout=5s --start-period=40s --retries=3 \
  CMD curl -fsS "http://127.0.0.1:8096/web/index.html" >/dev/null || exit 1

CMD ["/opt/jellyfin/jellyfin", "--datadir", "/config", "--cachedir", "/cache", "--webdir", "/opt/jellyfin/jellyfin-web"]
