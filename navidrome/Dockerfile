# syntax=docker/dockerfile:1

ARG NAVIDROME_REF=v0.61.1
ARG TAGLIB_VERSION=2.2.1
ARG JEMALLOC_VERSION=5.3.0
ARG FFMPEG_VERSION=8.1
ARG NAVIDROME_BUILD_CORES=2
ARG GOMEMLIMIT=6GiB
ARG SCANSCHEDULE=0
ARG CPU_OPTIMIZATION_FLAGS="-O3 -march=znver3 -mtune=znver3 -DNDEBUG -ffunction-sections -fdata-sections"
ARG LTO_FLAGS="-flto=thin"
ARG GOAMD64_VERSION=v3
ARG RUST_TARGET_CPU=znver3

# ── 체크섬 ──────────────────────────────────────────────────────────────────
ARG JEMALLOC_SHA256="2db82d1e7119df3e71b7640219b6dfe84789bc0537983c3b7ac4f7189aecfeaa"
ARG FFMPEG_SHA256="c07039598df7d64d3c8b42c4e25b1959fc908621c6f6c2946881133f3b27eda2"
ARG TAGLIB_SHA256="7e76b5299dcef427c486bffe455098470c8da91cf3ccb9ea804893df57389b5e"

# ── 베이스 이미지 digest 고정 ────────────────────────────────────────────────
ARG DEBIAN_TRIXIE_DIGEST="sha256:4ffb3a1511099754cddc70eb1b12e50ffdb67619aa0ab6c13fcd800a78ef7c7a"
ARG NODE_DIGEST="sha256:b506e7321f176aae77317f99d67a24b272c1f09f1d10f1761f2773447d8da26c"
ARG GOLANG_DIGEST="sha256:4f4ab2c90005e7e63cb631f0b4427f05422f241622ee3ec4727cc5febbf83e34"
ARG RUST_DIGEST="sha256:cf09adf8c3ebaba10779e5c23ff7fe4df4cccdab8a91f199b0c142c53fef3e1a"

# Source Stage
FROM debian:trixie-slim@${DEBIAN_TRIXIE_DIGEST} AS source
ARG NAVIDROME_REF
RUN apt-get update && apt-get install -y --no-install-recommends \
        git ca-certificates && \
    rm -rf /var/lib/apt/lists/*
WORKDIR /src
RUN git clone --branch "${NAVIDROME_REF}" --depth=1 \
        https://github.com/navidrome/navidrome.git . && \
    git rev-parse --short HEAD > /src/.git_sha

# Jemalloc Builder Stage
FROM debian:trixie-slim@${DEBIAN_TRIXIE_DIGEST} AS jemalloc-builder
ARG JEMALLOC_VERSION
ARG JEMALLOC_SHA256
ARG NAVIDROME_BUILD_CORES
ARG CPU_OPTIMIZATION_FLAGS
ARG LTO_FLAGS
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential clang lld llvm autoconf automake libtool bzip2 wget ca-certificates && \
    rm -rf /var/lib/apt/lists/*
WORKDIR /build
RUN wget -qO jemalloc.tar.bz2 \
        "https://github.com/jemalloc/jemalloc/releases/download/${JEMALLOC_VERSION}/jemalloc-${JEMALLOC_VERSION}.tar.bz2" && \
    echo "${JEMALLOC_SHA256}  jemalloc.tar.bz2" | sha256sum -c -
WORKDIR /build/jemalloc-${JEMALLOC_VERSION}
RUN tar -xjf /build/jemalloc.tar.bz2 --strip-components=1 -C .
RUN CC=clang CXX=clang++ \
    CFLAGS="${CPU_OPTIMIZATION_FLAGS} ${LTO_FLAGS}" \
    CXXFLAGS="${CPU_OPTIMIZATION_FLAGS} ${LTO_FLAGS}" \
    LDFLAGS="${LTO_FLAGS} -fuse-ld=lld" \
    ./configure --prefix=/usr/local --disable-cxx && \
    make -j${NAVIDROME_BUILD_CORES} install && \
    find /usr/local/lib -name "libjemalloc.so.*" ! -type l \
        -exec strip --strip-unneeded {} +

# FFmpeg Builder Stage (with enhanced static linking)
FROM debian:trixie-slim@${DEBIAN_TRIXIE_DIGEST} AS ffmpeg-builder
ARG FFMPEG_VERSION
ARG FFMPEG_SHA256
ARG NAVIDROME_BUILD_CORES
ARG CPU_OPTIMIZATION_FLAGS
ARG LTO_FLAGS
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential clang lld llvm pkg-config \
        yasm nasm wget ca-certificates \
        libmp3lame-dev libopus-dev libvorbis-dev && \
    rm -rf /var/lib/apt/lists/*
WORKDIR /build
RUN wget -qO ffmpeg.tar.bz2 "https://ffmpeg.org/releases/ffmpeg-${FFMPEG_VERSION}.tar.bz2" && \
    echo "${FFMPEG_SHA256}  ffmpeg.tar.bz2" | sha256sum -c -
WORKDIR /build/ffmpeg-${FFMPEG_VERSION}
RUN tar -xjf /build/ffmpeg.tar.bz2 --strip-components=1 -C .
RUN ./configure \
        --cc=clang --cxx=clang++ \
        --extra-cflags="${CPU_OPTIMIZATION_FLAGS} ${LTO_FLAGS}" \
        --extra-ldflags="${LTO_FLAGS} -fuse-ld=lld" \
        --disable-everything \
        --disable-ffplay \
        --disable-ffprobe \
        --disable-doc \
        --enable-avcodec \
        --enable-avformat \
        --enable-avfilter \
        --enable-swresample \
        --enable-protocol=file,pipe \
        --enable-demuxer=mp3,aac,flac,ogg,wav,aiff,mov,matroska,opus,ape,wv,dsf,caf \
        --enable-decoder=mp3,mp3float,aac,aac_fixed,flac,vorbis,opus,alac,\
        pcm_s16le,pcm_s16be,pcm_s24le,pcm_s32le,pcm_f32le,wavpack,ape,\
        dsd_lsbf_planar,dsd_msbf_planar \
        --enable-encoder=libmp3lame,libopus,libvorbis,flac,aac,pcm_s16le \
        --enable-muxer=mp3,flac,ogg,wav,opus,adts \
        --enable-filter=anull,aresample,volume,atrim,afade,aformat \
        --enable-bsf=aac_adtstoasc \
        --enable-libmp3lame \
        --enable-libopus \
        --enable-libvorbis \
        --prefix=/usr/local \
        --enable-static --disable-shared && \ # <-- Enhanced static linking
    make -j${NAVIDROME_BUILD_CORES} install && \
    strip --strip-unneeded /usr/local/bin/ffmpeg

# Rust Builder Stage (with FFmpeg wrapper)
FROM rust:1.94.1-slim@${RUST_DIGEST} AS rust-builder
ARG NAVIDROME_BUILD_CORES
ARG RUST_TARGET_CPU
RUN apt-get update && apt-get install -y --no-install-recommends \
        musl-tools build-essential ca-certificates && \
    rm -rf /var/lib/apt/lists/* && \
    rustup target add x86_64-unknown-linux-musl
WORKDIR /build
RUN mkdir -p /out entrypoint/src healthcheck/src ffmpeg-wrapper/src

# Existing entrypoint and healthcheck Cargo.toml and main.rs
RUN cat > Cargo.toml <<\"TOML\"
[workspace]
members = ["entrypoint", "healthcheck", "ffmpeg-wrapper"]
resolver = "2"
[profile.release]
opt-level = 3
lto = "thin"
codegen-units = 1
strip = true
panic = "abort"
TOML

RUN cat > entrypoint/Cargo.toml <<\"TOML\"
[package]
name = "entrypoint"
version = "0.1.0"
edition = "2021"
[dependencies]
rusqlite = { version = "0.31", features = ["bundled"] }
TOML
RUN cat > entrypoint/src/main.rs <<\"RUST_SRC\"
use std::env;
use std::os::unix::process::CommandExt;
use std::path::Path;
use std::process::Command;
fn wal_checkpoint() {
    let db_path = match env::var("ND_DBPATH") {
        Ok(v) => v,
        Err(_) => return,
    };
    let file = db_path.split(\"?\").next().unwrap_or("\").trim();
    if file.is_empty() || !Path::new(file).exists() {
        return;
    }
    if let Ok(conn) = rusqlite::Connection::open(file) {
        let _ = conn.execute_batch(
            \"PRAGMA wal_autocheckpoint=4000; PRAGMA wal_checkpoint(PASSIVE);\",
        );
    }
}
fn main() {
    wal_checkpoint();
    let args: Vec<String> = env::args().skip(1).collect();
    let err = Command::new(\"/app/navidrome\").args(&args).exec();
    eprintln!(\"[entrypoint] exec failed: {err}\");
    std::process::exit(1);
}
RUST_SRC

RUN cat > healthcheck/Cargo.toml <<\"TOML\"
[package]
name = "healthcheck"
version = "0.1.0"
edition = "2021"
TOML
RUN cat > healthcheck/src/main.rs <<\"RUST_SRC\"
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
    let req = format!(
        \"GET /ping HTTP/1.0\\r\\nHost: 127.0.0.1:{port}\\r\\nConnection: close\\r\\n\\r\\n\"
    );
    if stream.write_all(req.as_bytes()).is_err() {
        std::process::exit(1);
    }
    let mut buf = [0u8; 512];
    let n = stream.read(&mut buf).unwrap_or(0);
    let resp = std::str::from_utf8(&buf[..n]).unwrap_or("\");
    if resp.starts_with(\"HTTP/1.\") && resp.contains(\" 200 \") {
        std::process::exit(0);
    }
    std::process::exit(1);
}
RUST_SRC

# New FFmpeg Wrapper (Rust)
RUN cat > ffmpeg-wrapper/Cargo.toml <<\"TOML\"
[package]
name = "ffmpeg-wrapper"
version = "0.1.0"
edition = "2021"
[dependencies]
# Add dependencies for process control, error handling, etc.
# For example: tokio = { version = \"1\", features = [\"full\"] }, anyhow = \"1.0\"
TOML
RUN cat > ffmpeg-wrapper/src/main.rs <<\"RUST_FFMPEG_WRAPPER_SRC\"
// Placeholder for Rust FFmpeg wrapper logic
// This would parse arguments, set FFMPEG_THREADS dynamically, and execute ffmpeg.real
use std::env;
use std::process::{Command, exit};

fn main() {
    let args: Vec<String> = env::args().skip(1).collect();
    let ffmpeg_threads_str = env::var(\"FFMPEG_THREADS\").unwrap_or_else(|_| \"2\".to_string());
    let threads = ffmpeg_threads_str.parse::<u32>().unwrap_or(2);

    let mut cmd = Command::new(\"/usr/local/bin/ffmpeg.real\");
    cmd.arg(\"-threads\").arg(threads.to_string());
    cmd.args(&args);

    let status = cmd.status().expect(\"Failed to execute ffmpeg.real\");
    exit(status.code().unwrap_or(1));
}
RUST_FFMPEG_WRAPPER_SRC

RUN --mount=type=cache,target=/usr/local/cargo/registry \
    --mount=type=cache,target=/usr/local/cargo/git \
    --mount=type=cache,target=/build/target \
    CARGO_TARGET_X86_64_UNKNOWN_LINUX_MUSL_LINKER=musl-gcc \
    CC_x86_64_unknown_linux_musl=musl-gcc \
    RUSTFLAGS=\"-C target-cpu=${RUST_TARGET_CPU} -C opt-level=3 -C lto=thin -C codegen-units=1\" \
    cargo build --release --target x86_64-unknown-linux-musl -j${NAVIDROME_BUILD_CORES} && \
    cp target/x86_64-unknown-linux-musl/release/entrypoint /out/entrypoint && \
    cp target/x86_64-unknown-linux-musl/release/healthcheck /out/healthcheck && \
    cp target/x86_64-unknown-linux-musl/release/ffmpeg-wrapper /out/ffmpeg-wrapper

# Node.js Builder Stage
FROM node:24.14.1-bookworm-slim@${NODE_DIGEST} AS jsbuilder
WORKDIR /src/ui
COPY --from=source /src/ui ./
RUN --mount=type=cache,target=/root/.npm \
    npm ci --prefer-offline --no-audit --fund=false && npm run build

# Go Builder Stage (with Mold linker, PGO removed)
FROM golang:1.26.2-bookworm@${GOLANG_DIGEST} AS gobuilder
ARG TAGLIB_VERSION
ARG TAGLIB_SHA256
ARG NAVIDROME_REF
ARG NAVIDROME_BUILD_CORES
ARG CPU_OPTIMIZATION_FLAGS
ARG LTO_FLAGS
ARG GOAMD64_VERSION
RUN apt-get update && apt-get install -y --no-install-recommends \
        clang lld llvm make cmake zlib1g-dev ca-certificates \
        pkg-config wget libutfcpp-dev mold && \
    rm -rf /var/lib/apt/lists/*
WORKDIR /taglib-build
RUN wget -qO taglib.tar.gz \
        \"https://github.com/taglib/taglib/releases/download/v${TAGLIB_VERSION}/taglib-${TAGLIB_VERSION}.tar.gz\" && \
    echo \"${TAGLIB_SHA256}  taglib.tar.gz\" | sha256sum -c - && \
    tar -xzf taglib.tar.gz && cd \"taglib-${TAGLIB_VERSION}\" && \
    cmake -DCMAKE_BUILD_TYPE=Release \
          -DBUILD_SHARED_LIBS=OFF \
          -DCMAKE_C_COMPILER=clang \
          -DCMAKE_CXX_COMPILER=clang++ \
          -DCMAKE_AR=llvm-ar \
          -DCMAKE_RANLIB=llvm-ranlib \
          -DCMAKE_C_FLAGS=\"${CPU_OPTIMIZATION_FLAGS} ${LTO_FLAGS} -fPIC\" \
          -DCMAKE_CXX_FLAGS=\"${CPU_OPTIMIZATION_FLAGS} ${LTO_FLAGS} -fPIC\" \
          -DCMAKE_INSTALL_PREFIX=/usr/local . && \
    make -j${NAVIDROME_BUILD_CORES} install
WORKDIR /src
COPY --from=source /src/go.mod /src/go.sum ./
RUN --mount=type=cache,target=/go/pkg/mod go mod download
COPY --from=source /src ./
COPY --from=jsbuilder /src/ui/build ./ui/build/

ENV GOAMD64=${GOAMD64_VERSION} \
    CGO_ENABLED=1 \
    PKG_CONFIG_PATH=/usr/local/lib/pkgconfig \
    CC=clang \
    CXX=clang++ \
    CGO_CFLAGS=\"${CPU_OPTIMIZATION_FLAGS} ${LTO_FLAGS}\" \
    CGO_LDFLAGS=\"${LTO_FLAGS} -fuse-ld=mold -L/usr/local/lib -lstdc++ -lz -lm -Wl,--gc-sections -Wl,--as-needed\"
RUN --mount=type=cache,target=/root/.cache/go-build \
    --mount=type=cache,target=/go/pkg/mod \
    GIT_SHA=\"$(cat /src/.git_sha 2>/dev/null || echo dev)\" && \
    mkdir -p /out && \
    GOOS=linux GOARCH=amd64 go build -p ${NAVIDROME_BUILD_CORES} \
        -trimpath -buildvcs=false \
        -tags=\"netgo sqlite_fts5 sqlite_foreign_keys embed\" \
        -ldflags=\"-s -w -buildid= -X github.com/navidrome/navidrome/consts.gitSha=${GIT_SHA} -X github.com/navidrome/navidrome/consts.gitTag=${NAVIDROME_REF}\" \
        -o /out/navidrome .

# Release Stage
FROM debian:trixie-slim@${DEBIAN_TRIXIE_DIGEST} AS release
LABEL maintainer=\"JBS Networks\"
LABEL optimization=\"Zen3/Clang/ThinLTO/Jemalloc/Custom-FFmpeg/RustEntrypoint/RustHealthcheck/Mold/StaticFFmpeg/RustFFmpegWrapper\"
LABEL org.opencontainers.image.source=\"https://github.com/navidrome/navidrome\"

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates zlib1g libstdc++6 tzdata \
        libmp3lame0 libopus0 libvorbis0a libvorbisenc2 libvorbisfile3 && \
    rm -rf /var/lib/apt/lists/*

COPY --from=ffmpeg-builder /usr/local/bin/ffmpeg /usr/local/bin/ffmpeg.real # Renamed to .real
COPY --from=jemalloc-builder /usr/local/lib/libjemalloc.so.2 /usr/local/lib/

RUN echo \"/usr/local/lib\" > /etc/ld.so.conf.d/local.conf && ldconfig

# Use Rust FFmpeg wrapper
COPY --chmod=755 --from=rust-builder /out/ffmpeg-wrapper /usr/local/bin/ffmpeg

RUN groupadd -g 1000 navidrome && \
    useradd -u 1000 -g 1000 -M -d /nonexistent -s /usr/sbin/nologin navidrome && \
    mkdir -p /app /data /music /data/cache && \
    touch /.nddockerenv && \
    chown -R 1000:1000 /app /data /music

COPY --chown=1000:1000 --chmod=755 --from=gobuilder /out/navidrome /app/navidrome
COPY --chmod=755 --from=rust-builder /out/entrypoint /entrypoint
COPY --chmod=755 --from=rust-builder /out/healthcheck /usr/local/bin/healthcheck

USER 1000:1000
VOLUME [\"/data\", \"/music\"]

ARG NAVIDROME_BUILD_CORES
ARG GOMEMLIMIT
ARG SCANSCHEDULE

ENV TZ=Asia/Seoul \
    LD_PRELOAD=/usr/local/lib/libjemalloc.so.2 \
    MALLOC_CONF=\"background_thread:true,metadata_thp:auto,percpu_arena:percpu,tcache_max:32768,dirty_decay_ms:10000,muzzy_decay_ms:20000,stats_print:false\" \
    GOMEMLIMIT=${GOMEMLIMIT} \
    FFMPEG_THREADS=${NAVIDROME_BUILD_CORES} \
    ND_SCANNER_SCHEDULE=${SCANSCHEDULE} \
    ND_MUSICFOLDER=/music \
    ND_DATAFOLDER=/data \
    ND_CONFIGFILE=/data/navidrome.toml \
    ND_CACHEFOLDER=/data/cache \
    ND_DBPATH=\"/data/navidrome.db?cache=shared&_journal_mode=WAL&_synchronous=NORMAL&_timeout=30000&_foreign_keys=on\" \
    ND_TRANSCODINGCACHESIZE=1000MiB \
    ND_IMAGECACHESIZE=100MiB \
    ND_COVERJPEGQUALITY=85 \
    ND_ENABLEARTWORKPRECACHE=true \
    ND_ENABLETRANSCODINGCONFIG=true \
    ND_AUTOPLAYQUEUE=false \
    ND_ENABLEGRAVATAR=true \
    ND_DEFAULTLANGUAGE=ko \
    ND_LOGLEVEL=info \
    ND_PORT=4533

EXPOSE 4533

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
    CMD [\"/usr/local/bin/healthcheck\"]

WORKDIR /app
ENTRYPOINT [\"/entrypoint\"]
