# syntax=docker/dockerfile:1.7

# =========================================================
# JBS Networks Navidrome Ultra 6.0
# AMD EPYC Zen3 Dedicated Edition
# ALAC Source / Opus-MP3 Transcode / WebP Artwork Cache
#
# Core:
#   Navidrome v0.61.2
#   Go 1.26.3 / Node 24 LTS / Rust 1.95.0
#   FFmpeg 8.1.1 / libopus 1.6.1 / LAME 3.100
#   TagLib 2.3 / jemalloc 5.3.1
#
# Fixed:
#   - preflight --strict now actually stops startup
#   - heredoc + && split into separate RUN blocks
#   - base image tags changed to safer existing-family tags
#   - SQLITE_DQS=0 removed
#   - SQLITE_OMIT_LOAD_EXTENSION removed from CFLAGS/build tags
#   - /usr/local whole COPY removed
#   - SHA256 + tar sanity checks added
#   - ND_DBPATH uses _locking_mode=NORMAL
#   - unsupported _stmt_cache_size removed from ND_DBPATH
#   - MALLOC_CONF stats_print:false removed
#   - preflight respects custom ND_FFMPEGPATH and .real path
#   - Opus/LAME autotools builds force lld via CC/CXX
#   - Opus/LAME autotools builds do not pass lld-only --lto-O3
#
# Policy:
#   - AMD EPYC Zen3 only
#   - No Python
#   - No cover materializer
#   - Rust helpers included as static musl binaries
#   - FFmpeg focused on Opus/MP3 transcoding
#   - AAC/FLAC output transcode intentionally excluded
#   - WebP artwork cache enabled
#   - SQLite WAL/FTS5/STAT4/mmap optimized
# =========================================================

ARG DEBIAN_IMAGE=debian:trixie-slim
ARG NODE_IMAGE=node:24-bookworm-slim
ARG GOLANG_IMAGE=golang:1.26.3-bookworm
ARG RUST_IMAGE=rust:1.95.0-bookworm

ARG NAVIDROME_REF=v0.61.2

ARG JEMALLOC_VERSION=5.3.1
ARG FFMPEG_VERSION=8.1.1
ARG OPUS_VERSION=1.6.1
ARG LAME_VERSION=3.100
ARG TAGLIB_VERSION=2.3

ARG NAVIDROME_BUILD_CORES=4
ARG FFMPEG_THREADS=2
ARG GOMEMLIMIT=6GiB
ARG GOMAXPROCS=4
ARG GOGC=125
ARG SCANSCHEDULE=0
ARG GOAMD64_VERSION=v3
ARG RUST_TARGET_CPU=znver3

ARG CPU_OPTIMIZATION_FLAGS="-O3 -march=znver3 -mtune=znver3 -DNDEBUG -ffunction-sections -fdata-sections -pipe -fno-plt -falign-functions=32"
ARG THIN_LTO_FLAGS="-flto=thin"
ARG FULL_LTO_FLAGS="-flto"
ARG LLD_FLAGS="-fuse-ld=lld -Wl,-O2 -Wl,--gc-sections -Wl,--as-needed -Wl,-z,relro,-z,now"
ARG LLD_LTO_FLAGS="-Wl,--lto-O3"

ARG SQLITE_EXTRA_CFLAGS="\
-DSQLITE_ENABLE_FTS5 \
-DSQLITE_ENABLE_STAT4 \
-DSQLITE_ENABLE_JSON1 \
-DSQLITE_OMIT_SHARED_CACHE \
-DSQLITE_DEFAULT_WAL_AUTOCHECKPOINT=4096 \
-DSQLITE_DEFAULT_WAL_SYNCHRONOUS=1 \
-DSQLITE_TEMP_STORE=2 \
-DSQLITE_DEFAULT_MMAP_SIZE=268435456 \
-DSQLITE_MAX_MMAP_SIZE=1073741824 \
-DSQLITE_DEFAULT_CACHE_SIZE=-262144 \
-DSQLITE_DEFAULT_MEMSTATUS=0 \
-DSQLITE_LIKE_DOESNT_MATCH_BLOBS \
-DSQLITE_USE_ALLOCA"

ARG JEMALLOC_SHA256="3826bc80232f22ed5c4662f3034f799ca316e819103bdc7bb99018a421706f92"
ARG FFMPEG_SHA256="b6863adde98898f42602017462871b5f6333e65aec803fdd7a6308639c52edf3"
ARG OPUS_SHA256="6ffcb593207be92584df15b32466ed64bbec99109f007c82205f0194572411a1"
ARG TAGLIB_SHA256="7349f6fd942418bc7009ebe743eb7c9d055f02921ec56fa436ec25007c47fd38"
ARG LAME_SHA256="ddfe36cab873794038ae2c1210557ad34857a4b6bdc515785d1da9e175b1da1e"

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
ARG THIN_LTO_FLAGS
ARG LLD_FLAGS

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

RUN wget --https-only --max-redirect=3 -qO jemalloc.tar.bz2 \
      "https://github.com/jemalloc/jemalloc/releases/download/${JEMALLOC_VERSION}/jemalloc-${JEMALLOC_VERSION}.tar.bz2" && \
    echo "${JEMALLOC_SHA256}  jemalloc.tar.bz2" | sha256sum -c - && \
    tar -tjf jemalloc.tar.bz2 >/dev/null && \
    mkdir jemalloc && \
    tar -xjf jemalloc.tar.bz2 --strip-components=1 -C jemalloc

WORKDIR /build/jemalloc

RUN CC=clang CXX=clang++ \
    CFLAGS="${CPU_OPTIMIZATION_FLAGS} ${THIN_LTO_FLAGS}" \
    CXXFLAGS="${CPU_OPTIMIZATION_FLAGS} ${THIN_LTO_FLAGS}" \
    LDFLAGS="${THIN_LTO_FLAGS} ${LLD_FLAGS}" \
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
ARG FULL_LTO_FLAGS

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

RUN wget --https-only --max-redirect=3 -qO opus.tar.gz \
      "https://downloads.xiph.org/releases/opus/opus-${OPUS_VERSION}.tar.gz" && \
    echo "${OPUS_SHA256}  opus.tar.gz" | sha256sum -c - && \
    tar -tzf opus.tar.gz >/dev/null && \
    mkdir opus && \
    tar -xzf opus.tar.gz --strip-components=1 -C opus

WORKDIR /build/opus

# Autotools/libtool fix:
# - Force lld through CC/CXX.
# - Do not pass lld-only --lto-O3 here because libtool may call GNU ld.
RUN CC="clang -fuse-ld=lld" \
    CXX="clang++ -fuse-ld=lld" \
    AR=llvm-ar \
    RANLIB=llvm-ranlib \
    NM=llvm-nm \
    STRIP=llvm-strip \
    CFLAGS="${CPU_OPTIMIZATION_FLAGS} ${FULL_LTO_FLAGS}" \
    CXXFLAGS="${CPU_OPTIMIZATION_FLAGS} ${FULL_LTO_FLAGS}" \
    LDFLAGS="${FULL_LTO_FLAGS} -Wl,-O2 -Wl,--gc-sections -Wl,--as-needed -Wl,-z,relro,-z,now" \
    ./configure \
      --prefix=/usr/local \
      --enable-shared \
      --disable-static && \
    make -j"${NAVIDROME_BUILD_CORES}" install && \
    find /usr/local/lib -name "libopus.so.*" ! -type l -exec strip --strip-unneeded {} +

# =========================================================
# LAME MP3 encoder
# =========================================================

FROM ${DEBIAN_IMAGE} AS lame-builder

ARG LAME_VERSION
ARG LAME_SHA256
ARG NAVIDROME_BUILD_CORES
ARG CPU_OPTIMIZATION_FLAGS
ARG FULL_LTO_FLAGS

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
      ca-certificates \
      nasm

WORKDIR /build

RUN wget --https-only --max-redirect=3 -qO lame.tar.gz \
      "https://downloads.sourceforge.net/project/lame/lame/${LAME_VERSION}/lame-${LAME_VERSION}.tar.gz" && \
    echo "${LAME_SHA256}  lame.tar.gz" | sha256sum -c - && \
    tar -tzf lame.tar.gz >/dev/null && \
    mkdir lame && \
    tar -xzf lame.tar.gz --strip-components=1 -C lame

WORKDIR /build/lame

# Autotools/libtool fix:
# - Force lld through CC/CXX.
# - Do not pass lld-only --lto-O3 here because libtool may call GNU ld.
RUN CC="clang -fuse-ld=lld" \
    CXX="clang++ -fuse-ld=lld" \
    AR=llvm-ar \
    RANLIB=llvm-ranlib \
    NM=llvm-nm \
    STRIP=llvm-strip \
    CFLAGS="${CPU_OPTIMIZATION_FLAGS} ${FULL_LTO_FLAGS}" \
    CXXFLAGS="${CPU_OPTIMIZATION_FLAGS} ${FULL_LTO_FLAGS}" \
    LDFLAGS="${FULL_LTO_FLAGS} -Wl,-O2 -Wl,--gc-sections -Wl,--as-needed -Wl,-z,relro,-z,now" \
    ./configure \
      --prefix=/usr/local \
      --enable-shared \
      --disable-static \
      --disable-frontend && \
    make -j"${NAVIDROME_BUILD_CORES}" install && \
    find /usr/local/lib -name "libmp3lame.so.*" ! -type l -exec strip --strip-unneeded {} +

# =========================================================
# FFmpeg: Opus / MP3 specialized
# AAC/FLAC output transcode intentionally excluded.
# =========================================================

FROM ${DEBIAN_IMAGE} AS ffmpeg-builder

ARG FFMPEG_VERSION
ARG FFMPEG_SHA256
ARG NAVIDROME_BUILD_CORES
ARG CPU_OPTIMIZATION_FLAGS
ARG FULL_LTO_FLAGS
ARG LLD_FLAGS
ARG LLD_LTO_FLAGS

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
      xz-utils

COPY --from=opus-builder /usr/local/lib/libopus.so* /usr/local/lib/
COPY --from=opus-builder /usr/local/lib/pkgconfig/opus.pc /usr/local/lib/pkgconfig/
COPY --from=opus-builder /usr/local/include/opus /usr/local/include/opus

COPY --from=lame-builder /usr/local/lib/libmp3lame.so* /usr/local/lib/
COPY --from=lame-builder /usr/local/include/lame /usr/local/include/lame

RUN echo "/usr/local/lib" > /etc/ld.so.conf.d/local.conf && \
    ldconfig

ENV PKG_CONFIG_PATH=/usr/local/lib/pkgconfig:/usr/lib/pkgconfig:/usr/share/pkgconfig

WORKDIR /build

RUN wget --https-only --max-redirect=3 -qO ffmpeg.tar.xz \
      "https://ffmpeg.org/releases/ffmpeg-${FFMPEG_VERSION}.tar.xz" && \
    echo "${FFMPEG_SHA256}  ffmpeg.tar.xz" | sha256sum -c - && \
    tar -tJf ffmpeg.tar.xz >/dev/null && \
    mkdir ffmpeg && \
    tar -xJf ffmpeg.tar.xz --strip-components=1 -C ffmpeg

WORKDIR /build/ffmpeg

RUN ./configure \
      --cc=clang \
      --cxx=clang++ \
      --disable-runtime-cpudetect \
      --enable-hardcoded-tables \
      --disable-autodetect \
      --disable-network \
      --disable-debug \
      --disable-doc \
      --disable-ffplay \
      --enable-ffprobe \
      --disable-everything \
      --extra-cflags="${CPU_OPTIMIZATION_FLAGS} ${FULL_LTO_FLAGS}" \
      --extra-ldflags="${FULL_LTO_FLAGS} ${LLD_FLAGS} ${LLD_LTO_FLAGS}" \
      --extra-ldexeflags="-Wl,-O2,-z,relro,-z,now" \
      --enable-avcodec \
      --enable-avformat \
      --enable-avfilter \
      --enable-swresample \
      --enable-protocol=file,pipe \
      --enable-demuxer=mov,mp3,aac,flac,wav,aiff,ogg,opus \
      --enable-decoder=alac,aac,aac_fixed,mp3,mp3float,flac,opus,pcm_s16le,pcm_s16be,pcm_s24le,pcm_s24be,pcm_s32le,pcm_f32le \
      --enable-parser=aac,mpegaudio,flac,opus \
      --enable-encoder=libopus,libmp3lame,pcm_s16le \
      --enable-muxer=ogg,opus,mp3,wav \
      --enable-filter=anull,aresample,aformat,volume,atrim,afade \
      --enable-bsf=aac_adtstoasc \
      --enable-libopus \
      --enable-libmp3lame \
      --prefix=/usr/local && \
    make -j"${NAVIDROME_BUILD_CORES}" install && \
    strip --strip-unneeded /usr/local/bin/ffmpeg /usr/local/bin/ffprobe && \
    file /usr/local/bin/ffmpeg /usr/local/bin/ffprobe

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
      pkg-config \
      ca-certificates && \
    rustup target add x86_64-unknown-linux-musl

WORKDIR /build

RUN mkdir -p \
      entrypoint/src \
      healthcheck/src \
      sqlite-maint/src \
      cache-warm/src \
      ffmpeg-preflight/src

RUN cat > Cargo.toml <<'TOML'
[workspace]
members = [
  "entrypoint",
  "healthcheck",
  "sqlite-maint",
  "cache-warm",
  "ffmpeg-preflight"
]
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
TOML

RUN cat > entrypoint/src/main.rs <<'RUST'
use std::env;
use std::os::unix::process::CommandExt;
use std::process::Command;

fn env_true(name: &str, default: bool) -> bool {
    match env::var(name) {
        Ok(v) => matches!(v.to_ascii_lowercase().as_str(), "1" | "true" | "yes" | "on"),
        Err(_) => default,
    }
}

fn run_optional(cmd: &str, args: &[&str], enabled: bool) {
    if !enabled {
        return;
    }

    match Command::new(cmd).args(args).status() {
        Ok(status) if status.success() => {}
        Ok(status) => eprintln!(
            "[entrypoint] optional helper failed: {cmd} {:?} status={}",
            args, status
        ),
        Err(err) => eprintln!(
            "[entrypoint] optional helper could not start: {cmd} {:?}: {err}",
            args
        ),
    }
}

fn run_required(cmd: &str, args: &[&str], enabled: bool) {
    if !enabled {
        return;
    }

    match Command::new(cmd).args(args).status() {
        Ok(status) if status.success() => {}
        Ok(status) => {
            eprintln!(
                "[entrypoint] required helper failed: {cmd} {:?} status={}",
                args, status
            );
            std::process::exit(status.code().unwrap_or(1));
        }
        Err(err) => {
            eprintln!(
                "[entrypoint] required helper could not start: {cmd} {:?}: {err}",
                args
            );
            std::process::exit(1);
        }
    }
}

fn main() {
    run_required(
        "/usr/local/bin/jbs-ffmpeg-preflight",
        &["--strict"],
        env_true("JBS_FFMPEG_PREFLIGHT", true),
    );

    run_optional(
        "/usr/local/bin/jbs-sqlite-maint",
        &["startup"],
        env_true("JBS_SQLITE_MAINT", true),
    );

    if env_true("JBS_CACHE_WARM", true) {
        let limit = env::var("JBS_CACHE_WARM_LIMIT_MB").unwrap_or_else(|_| "512".to_string());
        run_optional(
            "/usr/local/bin/jbs-cache-warm",
            &["--limit-mb", &limit],
            true,
        );
    }

    let args: Vec<String> = env::args().skip(1).collect();
    let err = Command::new("/app/navidrome").args(&args).exec();

    eprintln!("[entrypoint] exec failed: {err}");
    std::process::exit(1);
}
RUST

RUN cat > healthcheck/Cargo.toml <<'TOML'
[package]
name = "healthcheck"
version = "0.1.0"
edition = "2021"
TOML

RUN cat > healthcheck/src/main.rs <<'RUST'
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
RUST

RUN cat > sqlite-maint/Cargo.toml <<'TOML'
[package]
name = "jbs-sqlite-maint"
version = "0.1.0"
edition = "2021"

[dependencies]
rusqlite = { version = "0.39.0", features = ["bundled"] }
TOML

RUN cat > sqlite-maint/src/main.rs <<'RUST'
use std::env;
use std::path::Path;
use std::time::Duration;

use rusqlite::{Connection, OpenFlags};

fn db_file_from_nd_dbpath(value: &str) -> Option<String> {
    let mut v = value.trim();

    if let Some(stripped) = v.strip_prefix("file:") {
        v = stripped;
    }

    let file = v.split('?').next().unwrap_or("").trim();

    if file.is_empty() {
        return None;
    }

    Some(file.to_string())
}

fn open_db() -> Option<Connection> {
    let db_path = env::var("ND_DBPATH").unwrap_or_else(|_| {
        "file:/data/navidrome.db?mode=rwc&_journal_mode=WAL&_synchronous=NORMAL".to_string()
    });

    let file = db_file_from_nd_dbpath(&db_path)?;

    if !Path::new(&file).exists() {
        eprintln!("[sqlite-maint] database does not exist yet: {file}");
        return None;
    }

    let uri = format!("file:{}?mode=rw", file);
    let conn = Connection::open_with_flags(
        &uri,
        OpenFlags::SQLITE_OPEN_READ_WRITE | OpenFlags::SQLITE_OPEN_URI,
    ).ok()?;

    let _ = conn.busy_timeout(Duration::from_secs(120));
    Some(conn)
}

fn run_sql(label: &str, sql: &str) -> i32 {
    let Some(conn) = open_db() else {
        return 0;
    };

    match conn.execute_batch(sql) {
        Ok(_) => {
            eprintln!("[sqlite-maint] {label}: ok");
            0
        }
        Err(err) => {
            eprintln!("[sqlite-maint] {label}: failed: {err}");
            1
        }
    }
}

fn main() {
    let mode = env::args().nth(1).unwrap_or_else(|| "startup".to_string());

    let code = match mode.as_str() {
        "startup" => run_sql(
            "startup",
            "
            PRAGMA journal_mode=WAL;
            PRAGMA synchronous=NORMAL;
            PRAGMA foreign_keys=ON;
            PRAGMA temp_store=MEMORY;
            PRAGMA mmap_size=268435456;
            PRAGMA analysis_limit=2000;
            PRAGMA optimize=0x10002;
            PRAGMA wal_checkpoint(PASSIVE);
            PRAGMA shrink_memory;
            ",
        ),
        "idle" => run_sql(
            "idle",
            "
            PRAGMA analysis_limit=1000;
            PRAGMA optimize;
            PRAGMA wal_checkpoint(PASSIVE);
            PRAGMA shrink_memory;
            ",
        ),
        "shutdown" => run_sql(
            "shutdown",
            "
            PRAGMA optimize;
            PRAGMA wal_checkpoint(TRUNCATE);
            PRAGMA shrink_memory;
            ",
        ),
        "doctor" => run_sql(
            "doctor",
            "
            PRAGMA quick_check;
            PRAGMA integrity_check;
            ",
        ),
        _ => {
            eprintln!("[sqlite-maint] usage: jbs-sqlite-maint [startup|idle|shutdown|doctor]");
            2
        }
    };

    std::process::exit(code);
}
RUST

RUN cat > cache-warm/Cargo.toml <<'TOML'
[package]
name = "jbs-cache-warm"
version = "0.1.0"
edition = "2021"

[dependencies]
walkdir = "2.5.0"
TOML

RUN cat > cache-warm/src/main.rs <<'RUST'
use std::env;
use std::fs::File;
use std::io::Read;
use std::path::{Path, PathBuf};

use walkdir::WalkDir;

const CHUNK: usize = 1024 * 1024;

fn parse_limit_mb() -> u64 {
    let mut args = env::args().skip(1);

    while let Some(arg) = args.next() {
        if arg == "--limit-mb" {
            if let Some(v) = args.next() {
                return v.parse::<u64>().unwrap_or(512);
            }
        }
    }

    env::var("JBS_CACHE_WARM_LIMIT_MB")
        .ok()
        .and_then(|v| v.parse::<u64>().ok())
        .unwrap_or(512)
}

fn read_some(path: &Path, remaining: &mut u64) {
    if *remaining == 0 {
        return;
    }

    let Ok(mut f) = File::open(path) else {
        return;
    };

    let mut buf = vec![0u8; CHUNK];

    loop {
        if *remaining == 0 {
            break;
        }

        let want = (*remaining).min(CHUNK as u64) as usize;

        match f.read(&mut buf[..want]) {
            Ok(0) => break,
            Ok(n) => *remaining = remaining.saturating_sub(n as u64),
            Err(_) => break,
        }
    }

    eprintln!("[cache-warm] warmed {}", path.display());
}

fn candidate_files() -> Vec<PathBuf> {
    let data = env::var("ND_DATAFOLDER").unwrap_or_else(|_| "/data".to_string());
    let cache = env::var("ND_CACHEFOLDER").unwrap_or_else(|_| "/cache".to_string());

    let mut out = vec![
        PathBuf::from(format!("{data}/navidrome.db")),
        PathBuf::from(format!("{data}/navidrome.db-wal")),
        PathBuf::from(format!("{data}/navidrome.db-shm")),
    ];

    for entry in WalkDir::new(cache)
        .max_depth(3)
        .follow_links(false)
        .into_iter()
        .filter_map(Result::ok)
    {
        if entry.file_type().is_file() {
            out.push(entry.path().to_path_buf());
        }

        if out.len() > 512 {
            break;
        }
    }

    out
}

fn main() {
    let mut remaining = parse_limit_mb().saturating_mul(1024 * 1024);

    if remaining == 0 {
        return;
    }

    for path in candidate_files() {
        if remaining == 0 {
            break;
        }

        read_some(&path, &mut remaining);
    }

    eprintln!("[cache-warm] done");
}
RUST

RUN cat > ffmpeg-preflight/Cargo.toml <<'TOML'
[package]
name = "jbs-ffmpeg-preflight"
version = "0.1.0"
edition = "2021"
TOML

RUN cat > ffmpeg-preflight/src/main.rs <<'RUST'
use std::env;
use std::path::Path;
use std::process::Command;

fn ffmpeg_path() -> String {
    let configured = env::var("ND_FFMPEGPATH")
        .unwrap_or_else(|_| "/usr/local/bin/ffmpeg".to_string());

    let real_candidate = format!("{configured}.real");

    if Path::new(&real_candidate).exists() {
        real_candidate
    } else {
        configured
    }
}

fn capture(args: &[&str]) -> Result<String, String> {
    let output = Command::new(ffmpeg_path())
        .args(args)
        .output()
        .map_err(|e| e.to_string())?;

    let mut s = String::new();
    s.push_str(&String::from_utf8_lossy(&output.stdout));
    s.push_str(&String::from_utf8_lossy(&output.stderr));

    if output.status.success() {
        Ok(s)
    } else {
        Err(s)
    }
}

fn require(haystack: &str, needle: &str, failures: &mut Vec<String>) {
    if !haystack.contains(needle) {
        failures.push(needle.to_string());
    }
}

fn main() {
    let strict = env::args().any(|a| a == "--strict");

    let path = ffmpeg_path();

    let enc = capture(&["-hide_banner", "-encoders"]).unwrap_or_default();
    let dec = capture(&["-hide_banner", "-decoders"]).unwrap_or_default();
    let mux = capture(&["-hide_banner", "-muxers"]).unwrap_or_default();
    let demux = capture(&["-hide_banner", "-demuxers"]).unwrap_or_default();
    let filters = capture(&["-hide_banner", "-filters"]).unwrap_or_default();

    let mut failures = Vec::new();

    require(&enc, "libopus", &mut failures);
    require(&enc, "libmp3lame", &mut failures);

    require(&dec, "alac", &mut failures);
    require(&dec, "aac", &mut failures);
    require(&dec, "mp3", &mut failures);
    require(&dec, "flac", &mut failures);
    require(&dec, "opus", &mut failures);

    require(&mux, "ogg", &mut failures);
    require(&mux, "mp3", &mut failures);
    require(&mux, "wav", &mut failures);

    require(&demux, "mov", &mut failures);
    require(&demux, "mp3", &mut failures);
    require(&demux, "flac", &mut failures);
    require(&demux, "wav", &mut failures);
    require(&demux, "ogg", &mut failures);

    require(&filters, "aresample", &mut failures);
    require(&filters, "aformat", &mut failures);

    if failures.is_empty() {
        eprintln!("[ffmpeg-preflight] ok: {path}");
        std::process::exit(0);
    }

    eprintln!(
        "[ffmpeg-preflight] missing capabilities from {path}: {}",
        failures.join(", ")
    );

    if strict {
        std::process::exit(1);
    }
}
RUST

RUN --mount=type=cache,target=/usr/local/cargo/registry \
    --mount=type=cache,target=/usr/local/cargo/git \
    --mount=type=cache,target=/build/target \
    CARGO_TARGET_X86_64_UNKNOWN_LINUX_MUSL_LINKER=musl-gcc \
    CC_x86_64_unknown_linux_musl=musl-gcc \
    RUSTFLAGS="-C target-cpu=${RUST_TARGET_CPU} -C opt-level=3 -C lto=thin -C codegen-units=1" \
    cargo build --release --target x86_64-unknown-linux-musl -j"${NAVIDROME_BUILD_CORES}" && \
    mkdir -p /out && \
    cp target/x86_64-unknown-linux-musl/release/entrypoint /out/entrypoint && \
    cp target/x86_64-unknown-linux-musl/release/healthcheck /out/healthcheck && \
    cp target/x86_64-unknown-linux-musl/release/jbs-sqlite-maint /out/jbs-sqlite-maint && \
    cp target/x86_64-unknown-linux-musl/release/jbs-cache-warm /out/jbs-cache-warm && \
    cp target/x86_64-unknown-linux-musl/release/jbs-ffmpeg-preflight /out/jbs-ffmpeg-preflight

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
ARG THIN_LTO_FLAGS
ARG LLD_FLAGS
ARG LLD_LTO_FLAGS
ARG GOAMD64_VERSION
ARG SQLITE_EXTRA_CFLAGS

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

RUN wget --https-only --max-redirect=3 -qO taglib.tar.gz \
      "https://github.com/taglib/taglib/releases/download/v${TAGLIB_VERSION}/taglib-${TAGLIB_VERSION}.tar.gz" && \
    echo "${TAGLIB_SHA256}  taglib.tar.gz" | sha256sum -c - && \
    tar -tzf taglib.tar.gz >/dev/null && \
    tar -xzf taglib.tar.gz && \
    cd "taglib-${TAGLIB_VERSION}" && \
    cmake -DCMAKE_BUILD_TYPE=Release \
      -DBUILD_SHARED_LIBS=OFF \
      -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=ON \
      -DCMAKE_C_COMPILER=clang \
      -DCMAKE_CXX_COMPILER=clang++ \
      -DCMAKE_AR=llvm-ar \
      -DCMAKE_RANLIB=llvm-ranlib \
      -DCMAKE_C_FLAGS="${CPU_OPTIMIZATION_FLAGS} ${THIN_LTO_FLAGS} -fPIC" \
      -DCMAKE_CXX_FLAGS="${CPU_OPTIMIZATION_FLAGS} ${THIN_LTO_FLAGS} -fPIC" \
      -DCMAKE_EXE_LINKER_FLAGS="${THIN_LTO_FLAGS} ${LLD_FLAGS} ${LLD_LTO_FLAGS}" \
      -DCMAKE_SHARED_LINKER_FLAGS="${THIN_LTO_FLAGS} ${LLD_FLAGS} ${LLD_LTO_FLAGS}" \
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
    CGO_CFLAGS="${CPU_OPTIMIZATION_FLAGS} ${THIN_LTO_FLAGS} ${SQLITE_EXTRA_CFLAGS}" \
    CGO_CXXFLAGS="${CPU_OPTIMIZATION_FLAGS} ${THIN_LTO_FLAGS}" \
    CGO_LDFLAGS="${THIN_LTO_FLAGS} ${LLD_FLAGS} ${LLD_LTO_FLAGS} -L/usr/local/lib -lstdc++ -lz -lm"

RUN --mount=type=cache,target=/root/.cache/go-build \
    --mount=type=cache,target=/go/pkg/mod \
    GIT_SHA="$(cat /src/.git_sha 2>/dev/null || echo dev)" && \
    EXTLDFLAGS="${THIN_LTO_FLAGS} ${LLD_FLAGS} ${LLD_LTO_FLAGS}" && \
    mkdir -p /out && \
    GOOS=linux GOARCH=amd64 go build -p "${NAVIDROME_BUILD_CORES}" \
      -trimpath \
      -buildvcs=false \
      -tags="netgo osusergo sqlite_fts5 sqlite_foreign_keys sqlite_stat4 sqlite_json embed" \
      -ldflags="-linkmode=external -extld=clang -extldflags '${EXTLDFLAGS}' -s -w -buildid= -X github.com/navidrome/navidrome/consts.gitSha=${GIT_SHA} -X github.com/navidrome/navidrome/consts.gitTag=${NAVIDROME_REF}" \
      -o /out/navidrome . && \
    file /out/navidrome

# =========================================================
# Runtime
# =========================================================

FROM ${DEBIAN_IMAGE} AS release

LABEL maintainer="JBS Networks" \
      optimization="JBS-Navidrome-Ultra-6.0/AMD-EPYC-Zen3/Opus-MP3/FullLTO-FFmpeg/SQLite-Ultra/Jemalloc/RustHelpers/WebP-Artwork" \
      org.opencontainers.image.source="https://github.com/navidrome/navidrome"

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates \
      zlib1g \
      libstdc++6 \
      tzdata && \
    rm -rf /var/lib/apt/lists/*

COPY --link --from=ffmpeg-builder /usr/local/bin/ffmpeg /usr/local/bin/ffmpeg
COPY --link --from=ffmpeg-builder /usr/local/bin/ffprobe /usr/local/bin/ffprobe
COPY --link --from=jemalloc-builder /usr/local/lib/libjemalloc.so.2 /usr/local/lib/
COPY --link --from=opus-builder /usr/local/lib/libopus.so* /usr/local/lib/
COPY --link --from=lame-builder /usr/local/lib/libmp3lame.so* /usr/local/lib/

RUN echo "/usr/local/lib" > /etc/ld.so.conf.d/local.conf && \
    ldconfig && \
    mv /usr/local/bin/ffmpeg /usr/local/bin/ffmpeg.real

RUN cat > /usr/local/bin/ffmpeg <<'SH'
#!/bin/sh
THREADS=$(printf '%d' "${FFMPEG_THREADS:-2}" 2>/dev/null)
if [ -z "$THREADS" ] || [ "$THREADS" -lt 1 ] 2>/dev/null; then
    THREADS=2
fi

exec /usr/local/bin/ffmpeg.real \
    -nostdin \
    -hide_banner \
    -nostats \
    -loglevel warning \
    -threads "$THREADS" \
    -filter_threads "$THREADS" \
    "$@"
SH

RUN chmod 755 /usr/local/bin/ffmpeg

RUN groupadd -g 1000 navidrome && \
    useradd -u 1000 -g 1000 -M -d /nonexistent -s /usr/sbin/nologin navidrome && \
    install -d -o 1000 -g 1000 -m 755 /app /data /music /cache /cache/tmp && \
    touch /.nddockerenv

COPY --link --chown=1000:1000 --chmod=755 --from=gobuilder /out/navidrome /app/navidrome

COPY --link --chmod=755 --from=rust-builder /out/entrypoint /entrypoint
COPY --link --chmod=755 --from=rust-builder /out/healthcheck /usr/local/bin/healthcheck
COPY --link --chmod=755 --from=rust-builder /out/jbs-sqlite-maint /usr/local/bin/jbs-sqlite-maint
COPY --link --chmod=755 --from=rust-builder /out/jbs-cache-warm /usr/local/bin/jbs-cache-warm
COPY --link --chmod=755 --from=rust-builder /out/jbs-ffmpeg-preflight /usr/local/bin/jbs-ffmpeg-preflight

USER 1000:1000

VOLUME ["/data", "/music", "/cache"]

ARG GOMEMLIMIT
ARG GOMAXPROCS
ARG GOGC
ARG SCANSCHEDULE
ARG FFMPEG_THREADS

ENV TZ=Asia/Seoul \
    TMPDIR=/cache/tmp \
    LD_PRELOAD=/usr/local/lib/libjemalloc.so.2 \
    MALLOC_CONF="background_thread:true,metadata_thp:auto,percpu_arena:percpu,dirty_decay_ms:30000,muzzy_decay_ms:60000,oversize_threshold:8388608" \
    GOMAXPROCS=${GOMAXPROCS} \
    GOGC=${GOGC} \
    GOMEMLIMIT=${GOMEMLIMIT} \
    GODEBUG=netdns=go \
    FFMPEG_THREADS=${FFMPEG_THREADS} \
    ND_ADDRESS=0.0.0.0 \
    ND_PORT=4533 \
    ND_FFMPEGPATH=/usr/local/bin/ffmpeg \
    ND_MUSICFOLDER=/music \
    ND_DATAFOLDER=/data \
    ND_CACHEFOLDER=/cache \
    ND_CONFIGFILE=/data/navidrome.toml \
    ND_DBPATH="file:/data/navidrome.db?mode=rwc&cache=private&_journal_mode=WAL&_synchronous=NORMAL&_locking_mode=NORMAL&_txlock=immediate&_busy_timeout=120000&_foreign_keys=on&_cache_size=-262144&_secure_delete=OFF" \
    ND_SCANNER_ENABLED=true \
    ND_SCANNER_SCHEDULE=${SCANSCHEDULE} \
    ND_SCANNER_SCANONSTARTUP=false \
    ND_SCANNER_WATCHERWAIT=0s \
    ND_SCANNER_PURGEMISSING=never \
    ND_SCANNER_FOLLOWSYMLINKS=false \
    ND_SCANNER_EXTRACTOR=taglib \
    ND_SEARCH_BACKEND=fts \
    ND_SEARCH_FULLSTRING=false \
    ND_UISEARCHDEBOUNCEMS=350 \
    ND_SMARTPLAYLISTREFRESHDELAY=5m \
    ND_MAXSIDEBARPLAYLISTS=50 \
    ND_ENABLEDOWNLOADS=true \
    ND_ENABLETRANSCODINGCANCELLATION=true \
    ND_ENABLETRANSCODINGCONFIG=true \
    ND_AUTOTRANSCODEDOWNLOAD=false \
    ND_DEFAULTDOWNSAMPLINGFORMAT=opus \
    ND_TRANSCODINGCACHESIZE=4096MiB \
    ND_IMAGECACHESIZE=768MiB \
    ND_COVERARTQUALITY=75 \
    ND_UICOVERARTSIZE=300 \
    ND_ENABLEWEBPENCODING=true \
    ND_COVERARTPRIORITY="cover.*,folder.*,front.*,embedded,external" \
    ND_ARTISTARTPRIORITY="artist.*,album/artist.*,external" \
    ND_DISCARTPRIORITY="disc*.*,cd*.*,cover.*,folder.*,front.*,discsubtitle,embedded" \
    ND_LYRICSPRIORITY=".lrc,.txt,embedded" \
    ND_ENABLEMEDIAFILECOVERART=false \
    ND_ENABLEARTWORKPRECACHE=true \
    ND_ENABLEARTWORKUPLOAD=true \
    ND_ENABLECOVERANIMATION=false \
    ND_ENABLEREPLAYGAIN=true \
    ND_ENABLENOWPLAYING=true \
    ND_ENABLEFAVOURITES=true \
    ND_ENABLESTARRATING=true \
    ND_AUTOIMPORTPLAYLISTS=false \
    ND_PLAYLISTSPATH="" \
    ND_ENABLEEXTERNALSERVICES=true \
    ND_ENABLEINSIGHTSCOLLECTOR=false \
    ND_AGENTS="deezer,lastfm,listenbrainz" \
    ND_DEEZER_ENABLED=true \
    ND_DEEZER_LANGUAGE="ko,en" \
    ND_LASTFM_ENABLED=true \
    ND_LASTFM_APIKEY="" \
    ND_LASTFM_SECRET="" \
    ND_LASTFM_LANGUAGE="ko,en" \
    ND_LASTFM_SCROBBLEFIRSTARTISTONLY=false \
    ND_LISTENBRAINZ_ENABLED=true \
    ND_LISTENBRAINZ_BASEURL=https://api.listenbrainz.org/1/ \
    ND_ENABLESCROBBLEHISTORY=true \
    ND_PROMETHEUS_ENABLED=false \
    ND_INSPECT_ENABLED=false \
    ND_PLUGINS_ENABLED=true \
    ND_PLUGINS_CACHESIZE=200MB \
    ND_PLUGINS_AUTORELOAD=false \
    ND_JUKEBOX_ENABLED=false \
    ND_ENABLEGRAVATAR=false \
    ND_ENABLELOGREDACTING=true \
    ND_ENABLESHARING=false \
    ND_DEFAULTLANGUAGE=ko \
    ND_DEFAULTTHEME=Dark \
    ND_LOGLEVEL=warn \
    ND_MAXIMAGEUPLOADSIZE=10MB \
    JBS_SQLITE_MAINT=true \
    JBS_CACHE_WARM=true \
    JBS_CACHE_WARM_LIMIT_MB=512 \
    JBS_FFMPEG_PREFLIGHT=true

EXPOSE 4533

STOPSIGNAL SIGTERM

HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD ["/usr/local/bin/healthcheck"]

WORKDIR /app

ENTRYPOINT ["/entrypoint"]
