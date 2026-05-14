# syntax=docker/dockerfile:1.7

# =========================================================
# JBS Networks Navidrome Ultra
# Zen3 / Go 1.26.3 / Node 24.15.0 LTS / Rust 1.95.0
# FFmpeg 8.1.1 / TagLib 2.3 / jemalloc 5.3.1 / libopus 1.6.1
# =========================================================
# 기준일: 2026-05-14

ARG DEBIAN_IMAGE=debian:trixie-slim
ARG NODE_IMAGE=node:24.15.0-bookworm-slim
ARG GOLANG_IMAGE=golang:1.26.3-bookworm
ARG RUST_IMAGE=rust:1.95.0-slim

ARG NAVIDROME_REF=v0.61.2
ARG TAGLIB_VERSION=2.3
ARG JEMALLOC_VERSION=5.3.1
ARG FFMPEG_VERSION=8.1.1
ARG OPUS_VERSION=1.6.1

ARG NAVIDROME_BUILD_CORES=2
ARG FFMPEG_THREADS=2
ARG GOMEMLIMIT=6GiB
ARG SCANSCHEDULE=0

ARG CPU_OPTIMIZATION_FLAGS="-O3 -march=znver3 -mtune=znver3 -DNDEBUG -ffunction-sections -fdata-sections -pipe -fno-plt -falign-functions=32"
ARG LTO_FLAGS="-flto=thin"
ARG GOAMD64_VERSION=v3
ARG RUST_TARGET_CPU=znver3

ARG JEMALLOC_SHA256="3826bc80232f22ed5c4662f3034f799ca316e819103bdc7bb99018a421706f92"
ARG FFMPEG_SHA256="b6863adde98898f42602017462871b5f6333e65aec803fdd7a6308639c52edf3"
ARG TAGLIB_SHA256="7349f6fd942418bc7009ebe743eb7c9d055f02921ec56fa436ec25007c47fd38"
ARG OPUS_SHA256="6ffcb593207be92584df15b32466ed64bbec99109f007c82205f0194572411a1"

# =========================================================
# Source
# =========================================================

FROM ${DEBIAN_IMAGE} AS source

ARG NAVIDROME_REF

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
      git \
      ca-certificates

WORKDIR /src

RUN --mount=type=cache,target=/root/.cache/git \
    git clone --branch "${NAVIDROME_REF}" --depth=1 https://github.com/navidrome/navidrome.git . && \
    git rev-parse --short HEAD > /src/.git_sha

# =========================================================
# jemalloc
# =========================================================

FROM ${DEBIAN_IMAGE} AS jemalloc-builder

ARG JEMALLOC_VERSION
ARG JEMALLOC_SHA256
ARG NAVIDROME_BUILD_CORES
ARG CPU_OPTIMIZATION_FLAGS
ARG LTO_FLAGS

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
      build-essential \
      clang \
      lld \
      llvm \
      autoconf \
      automake \
      libtool \
      bzip2 \
      wget \
      ca-certificates

WORKDIR /build

RUN wget -qO jemalloc.tar.bz2 \
      "https://github.com/jemalloc/jemalloc/releases/download/${JEMALLOC_VERSION}/jemalloc-${JEMALLOC_VERSION}.tar.bz2" && \
    echo "${JEMALLOC_SHA256}  jemalloc.tar.bz2" | sha256sum -c -

WORKDIR /build/jemalloc-${JEMALLOC_VERSION}

RUN tar -xjf /build/jemalloc.tar.bz2 --strip-components=1 -C . && \
    CC=clang CXX=clang++ \
    CFLAGS="${CPU_OPTIMIZATION_FLAGS} ${LTO_FLAGS}" \
    CXXFLAGS="${CPU_OPTIMIZATION_FLAGS} ${LTO_FLAGS}" \
    LDFLAGS="${LTO_FLAGS} -fuse-ld=lld" \
    ./configure \
      --prefix=/usr/local \
      --disable-cxx \
      --disable-stats \
      --enable-readlinkat && \
    make -j"${NAVIDROME_BUILD_CORES}" install && \
    find /usr/local/lib -name "libjemalloc.so.*" ! -type l -exec strip --strip-unneeded {} +

# =========================================================
# libopus
# =========================================================

FROM ${DEBIAN_IMAGE} AS opus-builder

ARG OPUS_VERSION
ARG OPUS_SHA256
ARG NAVIDROME_BUILD_CORES
ARG CPU_OPTIMIZATION_FLAGS
ARG LTO_FLAGS

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
      build-essential \
      clang \
      lld \
      llvm \
      pkg-config \
      autoconf \
      automake \
      libtool \
      wget \
      ca-certificates

WORKDIR /build

RUN wget -qO opus.tar.gz "https://downloads.xiph.org/releases/opus/opus-${OPUS_VERSION}.tar.gz" && \
    echo "${OPUS_SHA256}  opus.tar.gz" | sha256sum -c -

WORKDIR /build/opus-${OPUS_VERSION}

RUN tar -xzf /build/opus.tar.gz --strip-components=1 -C . && \
    CC=clang CXX=clang++ \
    CFLAGS="${CPU_OPTIMIZATION_FLAGS} ${LTO_FLAGS}" \
    CXXFLAGS="${CPU_OPTIMIZATION_FLAGS} ${LTO_FLAGS}" \
    LDFLAGS="${LTO_FLAGS} -fuse-ld=lld" \
    ./configure \
      --prefix=/usr/local \
      --enable-shared \
      --disable-static && \
    make -j"${NAVIDROME_BUILD_CORES}" install && \
    find /usr/local/lib -name "libopus.so.*" ! -type l -exec strip --strip-unneeded {} +

# =========================================================
# FFmpeg
# =========================================================

FROM ${DEBIAN_IMAGE} AS ffmpeg-builder

ARG FFMPEG_VERSION
ARG FFMPEG_SHA256
ARG NAVIDROME_BUILD_CORES
ARG CPU_OPTIMIZATION_FLAGS
ARG LTO_FLAGS

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
      build-essential \
      clang \
      lld \
      llvm \
      pkg-config \
      yasm \
      nasm \
      wget \
      ca-certificates \
      xz-utils \
      libmp3lame-dev \
      libvorbis-dev

COPY --from=opus-builder /usr/local /usr/local

RUN echo "/usr/local/lib" > /etc/ld.so.conf.d/local.conf && ldconfig

ENV PKG_CONFIG_PATH=/usr/local/lib/pkgconfig:/usr/lib/pkgconfig:/usr/share/pkgconfig

WORKDIR /build

RUN wget -qO ffmpeg.tar.xz "https://ffmpeg.org/releases/ffmpeg-${FFMPEG_VERSION}.tar.xz" && \
    echo "${FFMPEG_SHA256}  ffmpeg.tar.xz" | sha256sum -c -

WORKDIR /build/ffmpeg-${FFMPEG_VERSION}

RUN tar -xJf /build/ffmpeg.tar.xz --strip-components=1 -C . && \
    ./configure \
      --cc=clang \
      --cxx=clang++ \
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
      --extra-ldexeflags="-Wl,-O1,-z,relro,-z,now" \
      --enable-avcodec \
      --enable-avformat \
      --enable-avfilter \
      --enable-swresample \
      --enable-protocol=file,pipe \
      --enable-demuxer=mp3,aac,flac,ogg,wav,aiff,mov,matroska,opus,ape,wv,dsf,caf \
      --enable-decoder=mp3,mp3float,aac,aac_fixed,flac,vorbis,opus,alac,pcm_s16le,pcm_s16be,pcm_s24le,pcm_s32le,pcm_f32le,wavpack,ape,dsd_lsbf_planar,dsd_msbf_planar \
      --enable-encoder=libmp3lame,libopus,libvorbis,flac,aac,pcm_s16le \
      --enable-muxer=mp3,flac,ogg,wav,opus,adts \
      --enable-filter=anull,aresample,volume,atrim,afade,aformat \
      --enable-bsf=aac_adtstoasc \
      --enable-libmp3lame \
      --enable-libopus \
      --enable-libvorbis \
      --prefix=/usr/local && \
    make -j"${NAVIDROME_BUILD_CORES}" install && \
    strip --strip-unneeded /usr/local/bin/ffmpeg && \
    ldd /usr/local/bin/ffmpeg

# =========================================================
# Rust helper binaries
# =========================================================

FROM ${RUST_IMAGE} AS rust-builder

ARG NAVIDROME_BUILD_CORES
ARG RUST_TARGET_CPU

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
      musl-tools \
      build-essential \
      ca-certificates && \
    rustup target add x86_64-unknown-linux-musl

WORKDIR /build

RUN mkdir -p /out entrypoint/src healthcheck/src

RUN cat > Cargo.toml <<'TOML'
[workspace]
members = ["entrypoint", "healthcheck"]
resolver = "2"

[profile.release]
opt-level = 3
lto = "thin"
codegen-units = 1
strip = true
panic = "abort"
TOML

RUN cat > entrypoint/Cargo.toml <<'TOML'
[package]
name = "entrypoint"
version = "0.1.0"
edition = "2021"

[dependencies]
rusqlite = { version = "0.31", features = ["bundled"] }
TOML

RUN cat > entrypoint/src/main.rs <<'RUST_SRC'
use std::env;
use std::os::unix::process::CommandExt;
use std::path::Path;
use std::process::Command;

fn wal_checkpoint() {
    let db_path = match env::var("ND_DBPATH") {
        Ok(v) => v,
        Err(_) => return,
    };

    let file = db_path.split('?').next().unwrap_or("").trim();
    if file.is_empty() || !Path::new(file).exists() {
        return;
    }

    if let Ok(conn) = rusqlite::Connection::open(file) {
        let _ = conn.execute_batch(
            "PRAGMA wal_autocheckpoint=4000; PRAGMA wal_checkpoint(PASSIVE);",
        );
    }
}

fn main() {
    wal_checkpoint();

    let args: Vec<String> = env::args().skip(1).collect();
    let err = Command::new("/app/navidrome").args(&args).exec();

    eprintln!("[entrypoint] exec failed: {err}");
    std::process::exit(1);
}
RUST_SRC

RUN cat > healthcheck/Cargo.toml <<'TOML'
[package]
name = "healthcheck"
version = "0.1.0"
edition = "2021"
TOML

RUN cat > healthcheck/src/main.rs <<'RUST_SRC'
use std::env;
use std::io::{Read, Write};
use std::net::{SocketAddr, TcpStream};
use std::time::Duration;

fn main() {
    let port: u16 = env::var("ND_PORT")
        .unwrap_or_default()
        .parse()
        .unwrap_or(4533);

    let addr = SocketAddr::from(([127, 0, 0, 1], port));
    let timeout = Duration::from_secs(4);

    let mut stream = match TcpStream::connect_timeout(&addr, timeout) {
        Ok(s) => s,
        Err(_) => std::process::exit(1),
    };

    let _ = stream.set_read_timeout(Some(timeout));
    let _ = stream.set_write_timeout(Some(timeout));

    let req = format!(
        "GET /ping HTTP/1.0\r\nHost: 127.0.0.1:{port}\r\nConnection: close\r\n\r\n"
    );

    if stream.write_all(req.as_bytes()).is_err() {
        std::process::exit(1);
    }

    let mut buf = [0u8; 512];
    let n = stream.read(&mut buf).unwrap_or(0);
    let resp = std::str::from_utf8(&buf[..n]).unwrap_or("");

    if resp.starts_with("HTTP/1.") && resp.contains(" 200 ") {
        std::process::exit(0);
    }

    std::process::exit(1);
}
RUST_SRC

RUN --mount=type=cache,target=/usr/local/cargo/registry \
    --mount=type=cache,target=/usr/local/cargo/git \
    --mount=type=cache,target=/build/target \
    CARGO_TARGET_X86_64_UNKNOWN_LINUX_MUSL_LINKER=musl-gcc \
    CC_x86_64_unknown_linux_musl=musl-gcc \
    RUSTFLAGS="-C target-cpu=${RUST_TARGET_CPU} -C opt-level=3 -C lto=thin -C codegen-units=1" \
    cargo build --release --target x86_64-unknown-linux-musl -j"${NAVIDROME_BUILD_CORES}" && \
    cp target/x86_64-unknown-linux-musl/release/entrypoint /out/entrypoint && \
    cp target/x86_64-unknown-linux-musl/release/healthcheck /out/healthcheck

# =========================================================
# UI build
# =========================================================

FROM ${NODE_IMAGE} AS jsbuilder

WORKDIR /src/ui

COPY --link --from=source /src/ui ./

RUN --mount=type=cache,target=/root/.npm \
    npm ci --prefer-offline --no-audit --fund=false && \
    npm run build

# =========================================================
# Go / Navidrome build
# =========================================================

FROM ${GOLANG_IMAGE} AS gobuilder

ARG TAGLIB_VERSION
ARG TAGLIB_SHA256
ARG NAVIDROME_REF
ARG NAVIDROME_BUILD_CORES
ARG CPU_OPTIMIZATION_FLAGS
ARG LTO_FLAGS
ARG GOAMD64_VERSION

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
      clang \
      lld \
      llvm \
      make \
      cmake \
      zlib1g-dev \
      ca-certificates \
      pkg-config \
      wget \
      libutfcpp-dev

WORKDIR /taglib-build

RUN wget -qO taglib.tar.gz \
      "https://github.com/taglib/taglib/releases/download/v${TAGLIB_VERSION}/taglib-${TAGLIB_VERSION}.tar.gz" && \
    echo "${TAGLIB_SHA256}  taglib.tar.gz" | sha256sum -c - && \
    tar -xzf taglib.tar.gz && \
    cd "taglib-${TAGLIB_VERSION}" && \
    cmake -DCMAKE_BUILD_TYPE=Release \
      -DBUILD_SHARED_LIBS=OFF \
      -DCMAKE_C_COMPILER=clang \
      -DCMAKE_CXX_COMPILER=clang++ \
      -DCMAKE_AR=llvm-ar \
      -DCMAKE_RANLIB=llvm-ranlib \
      -DCMAKE_C_FLAGS="${CPU_OPTIMIZATION_FLAGS} ${LTO_FLAGS} -fPIC" \
      -DCMAKE_CXX_FLAGS="${CPU_OPTIMIZATION_FLAGS} ${LTO_FLAGS} -fPIC" \
      -DCMAKE_INSTALL_PREFIX=/usr/local . && \
    make -j"${NAVIDROME_BUILD_CORES}" install

WORKDIR /src

COPY --from=source /src/go.mod /src/go.sum ./

RUN --mount=type=cache,target=/go/pkg/mod \
    go mod download

COPY --from=source /src ./
COPY --link --from=jsbuilder /src/ui/build ./ui/build/

ENV GOAMD64=${GOAMD64_VERSION} \
    CGO_ENABLED=1 \
    PKG_CONFIG_PATH=/usr/local/lib/pkgconfig \
    CC=clang \
    CXX=clang++ \
    CGO_CFLAGS="${CPU_OPTIMIZATION_FLAGS} ${LTO_FLAGS}" \
    CGO_LDFLAGS="${LTO_FLAGS} -fuse-ld=lld -L/usr/local/lib -lstdc++ -lz -lm -Wl,--gc-sections -Wl,--as-needed"

RUN --mount=type=cache,target=/root/.cache/go-build \
    --mount=type=cache,target=/go/pkg/mod \
    GIT_SHA="$(cat /src/.git_sha 2>/dev/null || echo dev)" && \
    mkdir -p /out && \
    GOOS=linux GOARCH=amd64 go build -p "${NAVIDROME_BUILD_CORES}" \
      -trimpath \
      -buildvcs=false \
      -tags="netgo sqlite_fts5 sqlite_foreign_keys embed" \
      -ldflags="-s -w -buildid= -X github.com/navidrome/navidrome/consts.gitSha=${GIT_SHA} -X github.com/navidrome/navidrome/consts.gitTag=${NAVIDROME_REF}" \
      -o /out/navidrome . && \
    file /out/navidrome && \
    ldd /out/navidrome || true

# =========================================================
# Runtime
# =========================================================

FROM ${DEBIAN_IMAGE} AS release

LABEL maintainer="JBS Networks" \
      optimization="Zen3/Clang/ThinLTO/Jemalloc/Custom-FFmpeg/RustEntrypoint/RustHealthcheck" \
      org.opencontainers.image.source="https://github.com/navidrome/navidrome"

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates \
      zlib1g \
      libstdc++6 \
      tzdata \
      libmp3lame0 \
      libvorbis0a \
      libvorbisenc2 \
      libvorbisfile3

COPY --link --from=ffmpeg-builder /usr/local/bin/ffmpeg /usr/local/bin/ffmpeg
COPY --link --from=jemalloc-builder /usr/local/lib/libjemalloc.so.2 /usr/local/lib/
COPY --link --from=opus-builder /usr/local/lib/libopus.so* /usr/local/lib/

RUN echo "/usr/local/lib" > /etc/ld.so.conf.d/local.conf && \
    ldconfig && \
    mv /usr/local/bin/ffmpeg /usr/local/bin/ffmpeg.real && \
    cat > /usr/local/bin/ffmpeg <<'SH' && \
    chmod 755 /usr/local/bin/ffmpeg
#!/bin/sh
THREADS=$(printf '%d' "${FFMPEG_THREADS:-2}" 2>/dev/null)
if [ -z "$THREADS" ] || [ "$THREADS" -lt 1 ] 2>/dev/null; then
    THREADS=2
fi
exec /usr/local/bin/ffmpeg.real -threads "$THREADS" "$@"
SH

RUN groupadd -g 1000 navidrome && \
    useradd -u 1000 -g 1000 -M -d /nonexistent -s /usr/sbin/nologin navidrome && \
    install -d -o 1000 -g 1000 -m 755 /app /data /music /data/cache && \
    touch /.nddockerenv

COPY --link --chown=1000:1000 --chmod=755 --from=gobuilder /out/navidrome /app/navidrome
COPY --link --chmod=755 --from=rust-builder /out/entrypoint /entrypoint
COPY --link --chmod=755 --from=rust-builder /out/healthcheck /usr/local/bin/healthcheck

USER 1000:1000

VOLUME ["/data", "/music"]

ARG GOMEMLIMIT
ARG SCANSCHEDULE
ARG FFMPEG_THREADS

ENV TZ=Asia/Seoul \
    LD_PRELOAD=/usr/local/lib/libjemalloc.so.2 \
    MALLOC_CONF="background_thread:true,metadata_thp:auto,percpu_arena:percpu,dirty_decay_ms:10000,muzzy_decay_ms:20000,oversize_threshold:8388608,stats_print:false" \
    GOMEMLIMIT=${GOMEMLIMIT} \
    FFMPEG_THREADS=${FFMPEG_THREADS} \
    ND_SCANNER_SCHEDULE=${SCANSCHEDULE} \
    ND_MUSICFOLDER=/music \
    ND_DATAFOLDER=/data \
    ND_CONFIGFILE=/data/navidrome.toml \
    ND_CACHEFOLDER=/data/cache \
    ND_DBPATH="/data/navidrome.db?cache=shared&_journal_mode=WAL&_synchronous=NORMAL&_timeout=30000&_foreign_keys=on" \
    ND_TRANSCODINGCACHESIZE=1000MiB \
    ND_IMAGECACHESIZE=100MiB \
    ND_COVERJPEGQUALITY=85 \
    ND_MAXIMAGEUPLOADSIZE=10MB \
    ND_ENABLEARTWORKPRECACHE=true \
    ND_ENABLETRANSCODINGCONFIG=true \
    ND_AUTOPLAYQUEUE=false \
    ND_ENABLEGRAVATAR=false \
    ND_DEFAULTLANGUAGE=ko \
    ND_LOGLEVEL=info \
    ND_PORT=4533

EXPOSE 4533

HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
    CMD ["/usr/local/bin/healthcheck"]

WORKDIR /app

ENTRYPOINT ["/entrypoint"]
