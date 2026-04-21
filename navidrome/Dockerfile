# syntax=docker/dockerfile:1
# JBS Networks — Navidrome Ultra (Zen3 / Clang+ThinLTO / jemalloc / Custom-FFmpeg)
# v5.1 — libopus 1.6.1 적용 + pkg-config 안정화 + shared 명시

ARG NAVIDROME_REF=v0.61.2
ARG TAGLIB_VERSION=2.2.1
ARG JEMALLOC_VERSION=5.3.1
ARG FFMPEG_VERSION=8.1
ARG OPUS_VERSION=1.6.1
ARG NAVIDROME_BUILD_CORES=2
ARG GOMEMLIMIT=6GiB
ARG SCANSCHEDULE=0
ARG CPU_OPTIMIZATION_FLAGS="-O3 -march=znver3 -mtune=znver3 -DNDEBUG -ffunction-sections -fdata-sections -pipe -fno-plt -funroll-loops -falign-functions=32"
ARG LTO_FLAGS="-flto=thin"
ARG GOAMD64_VERSION=v3
ARG RUST_TARGET_CPU=znver3

# ── 체크섬 ─────────────────────────────────────────────
ARG JEMALLOC_SHA256="3826bc80232f22ed5c4662f3034f799ca316e819103bdc7bb99018a421706f92"
ARG FFMPEG_SHA256="c07039598df7d64d3c8b42c4e25b1959fc908621c6f6c2946881133f3b27eda2"
ARG TAGLIB_SHA256="7e76b5299dcef427c486bffe455098470c8da91cf3ccb9ea804893df57389b5e"
ARG OPUS_SHA256="6ffcb593207be92584df15b32466ed64bbec99109f007c82205f0194572411a1"

# ── 베이스 이미지 ─────────────────────────────────────
ARG DEBIAN_TRIXIE_DIGEST="sha256:4ffb3a1511099754cddc70eb1b12e50ffdb67619aa0ab6c13fcd800a78ef7c7a"
ARG NODE_DIGEST="sha256:b506e7321f176aae77317f99d67a24b272c1f09f1d10f1761f2773447d8da26c"
ARG GOLANG_DIGEST="sha256:4f4ab2c90005e7e63cb631f0b4427f05422f241622ee3ec4727cc5febbf83e34"
ARG RUST_DIGEST="sha256:cf09adf8c3ebaba10779e5c23ff7fe4df4cccdab8a91f199b0c142c53fef3e1a"

# ─────────────────────────────────────────────────────

FROM debian:trixie-slim@${DEBIAN_TRIXIE_DIGEST} AS source
ARG NAVIDROME_REF
RUN apt-get update && apt-get install -y --no-install-recommends git ca-certificates && rm -rf /var/lib/apt/lists/*
WORKDIR /src
RUN git clone --branch "${NAVIDROME_REF}" --depth=1 https://github.com/navidrome/navidrome.git . && \
    git rev-parse --short HEAD > /src/.git_sha

# ─────────────────────────────────────────────────────
# jemalloc
# ─────────────────────────────────────────────────────
FROM debian:trixie-slim@${DEBIAN_TRIXIE_DIGEST} AS jemalloc-builder
ARG JEMALLOC_VERSION JEMALLOC_SHA256 NAVIDROME_BUILD_CORES CPU_OPTIMIZATION_FLAGS LTO_FLAGS
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential clang lld llvm autoconf automake libtool bzip2 wget ca-certificates && rm -rf /var/lib/apt/lists/*
WORKDIR /build
RUN wget -qO jemalloc.tar.bz2 https://github.com/jemalloc/jemalloc/releases/download/${JEMALLOC_VERSION}/jemalloc-${JEMALLOC_VERSION}.tar.bz2 && \
    echo "${JEMALLOC_SHA256}  jemalloc.tar.bz2" | sha256sum -c -
WORKDIR /build/jemalloc-${JEMALLOC_VERSION}
RUN tar -xjf /build/jemalloc.tar.bz2 --strip-components=1 -C .
RUN CC=clang CXX=clang++ \
    CFLAGS="${CPU_OPTIMIZATION_FLAGS} ${LTO_FLAGS}" \
    CXXFLAGS="${CPU_OPTIMIZATION_FLAGS} ${LTO_FLAGS}" \
    LDFLAGS="${LTO_FLAGS} -fuse-ld=lld" \
    ./configure --prefix=/usr/local --disable-cxx --disable-stats --enable-readlinkat && \
    make -j${NAVIDROME_BUILD_CORES} install && \
    strip --strip-unneeded /usr/local/lib/libjemalloc.so.*

# ─────────────────────────────────────────────────────
# opus 1.6.1
# ─────────────────────────────────────────────────────
FROM debian:trixie-slim@${DEBIAN_TRIXIE_DIGEST} AS opus-builder
ARG OPUS_VERSION OPUS_SHA256 NAVIDROME_BUILD_CORES CPU_OPTIMIZATION_FLAGS LTO_FLAGS
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential clang lld llvm pkg-config autoconf automake libtool wget ca-certificates && rm -rf /var/lib/apt/lists/*
WORKDIR /build
RUN wget -qO opus.tar.gz https://downloads.xiph.org/releases/opus/opus-${OPUS_VERSION}.tar.gz && \
    echo "${OPUS_SHA256}  opus.tar.gz" | sha256sum -c -
WORKDIR /build/opus-${OPUS_VERSION}
RUN tar -xzf /build/opus.tar.gz --strip-components=1 -C .
RUN CC=clang CXX=clang++ \
    CFLAGS="${CPU_OPTIMIZATION_FLAGS} ${LTO_FLAGS}" \
    CXXFLAGS="${CPU_OPTIMIZATION_FLAGS} ${LTO_FLAGS}" \
    LDFLAGS="${LTO_FLAGS} -fuse-ld=lld" \
    ./configure --prefix=/usr/local --enable-shared --disable-static && \
    make -j${NAVIDROME_BUILD_CORES} install && \
    strip --strip-unneeded /usr/local/lib/libopus.so.*

# ─────────────────────────────────────────────────────
# ffmpeg
# ─────────────────────────────────────────────────────
FROM debian:trixie-slim@${DEBIAN_TRIXIE_DIGEST} AS ffmpeg-builder
ARG FFMPEG_VERSION FFMPEG_SHA256 NAVIDROME_BUILD_CORES CPU_OPTIMIZATION_FLAGS LTO_FLAGS
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential clang lld llvm pkg-config yasm nasm wget ca-certificates \
    libmp3lame-dev libvorbis-dev && rm -rf /var/lib/apt/lists/*
COPY --from=opus-builder /usr/local /usr/local
ENV PKG_CONFIG_PATH=/usr/local/lib/pkgconfig:/usr/lib/pkgconfig:/usr/share/pkgconfig
WORKDIR /build
RUN wget -qO ffmpeg.tar.bz2 https://ffmpeg.org/releases/ffmpeg-${FFMPEG_VERSION}.tar.bz2 && \
    echo "${FFMPEG_SHA256}  ffmpeg.tar.bz2" | sha256sum -c -
WORKDIR /build/ffmpeg-${FFMPEG_VERSION}
RUN tar -xjf /build/ffmpeg.tar.bz2 --strip-components=1 -C .
RUN ./configure \
    --cc=clang --cxx=clang++ \
    --cpu=znver3 \
    --disable-runtime-cpudetect \
    --enable-hardcoded-tables \
    --disable-autodetect \
    --disable-network \
    --disable-debug \
    --disable-doc \
    --disable-ffplay \
    --disable-ffprobe \
    --disable-everything \
    --extra-cflags="${CPU_OPTIMIZATION_FLAGS} ${LTO_FLAGS}" \
    --extra-ldflags="${LTO_FLAGS} -fuse-ld=lld -Wl,--gc-sections -Wl,--as-needed" \
    --enable-avcodec \
    --enable-avformat \
    --enable-avfilter \
    --enable-swresample \
    --enable-protocol=file,pipe \
    --enable-demuxer=mp3,aac,flac,ogg,wav,aiff,mov,matroska,opus,ape,wv,dsf,caf \
    --enable-decoder=mp3,aac,flac,vorbis,opus,alac,pcm_s16le \
    --enable-encoder=libmp3lame,libopus,libvorbis,flac,aac \
    --enable-muxer=mp3,flac,ogg,wav,opus,adts \
    --enable-filter=aresample \
    --enable-libopus \
    --enable-libmp3lame \
    --enable-libvorbis \
    --prefix=/usr/local && \
    make -j${NAVIDROME_BUILD_CORES} install && \
    strip --strip-unneeded /usr/local/bin/ffmpeg

# ─────────────────────────────────────────────────────
# runtime
# ─────────────────────────────────────────────────────
FROM debian:trixie-slim@${DEBIAN_TRIXIE_DIGEST} AS release
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates zlib1g libstdc++6 tzdata \
    libmp3lame0 libvorbis0a libvorbisenc2 libvorbisfile3 && rm -rf /var/lib/apt/lists/*

COPY --from=ffmpeg-builder /usr/local/bin/ffmpeg /usr/local/bin/ffmpeg
COPY --from=jemalloc-builder /usr/local/lib/libjemalloc.so.2 /usr/local/lib/
COPY --from=opus-builder /usr/local/lib/libopus.so* /usr/local/lib/

RUN echo "/usr/local/lib" > /etc/ld.so.conf.d/local.conf && ldconfig

RUN mv /usr/local/bin/ffmpeg /usr/local/bin/ffmpeg.real && \
    printf '#!/bin/sh\nexec /usr/local/bin/ffmpeg.real -threads ${FFMPEG_THREADS:-2} "$@"\n' > /usr/local/bin/ffmpeg && \
    chmod +x /usr/local/bin/ffmpeg

WORKDIR /app
