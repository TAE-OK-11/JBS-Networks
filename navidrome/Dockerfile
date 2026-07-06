# syntax=docker/dockerfile:1.7

# =========================================================
# JBS Networks Navidrome Ultra 6.1 Slim v9 Light Final
# AMD EPYC Zen3 Dedicated Edition
#
# Final merge:
#   - Base: v8 operational/security cleanup
#   - Update: Node 26.4.0
#   - Update: FFmpeg 8.1.2
#   - Update: rusqlite 0.40.1
#   - Light runtime: lower SQLite cache / mmap
#   - Light runtime: lower Go memory target
#   - Light runtime: jemalloc small-server profile
#   - Light runtime: disable startup cache warm by default
#   - Light runtime: disable artwork precache by default
# =========================================================

ARG DEBIAN_IMAGE=debian:trixie-slim@sha256:28de0877c2189802884ccd20f15ee41c203573bd87bb6b883f5f46362d24c5c2
ARG NODE_IMAGE=node:26.4.0-trixie-slim@sha256:a1d9d671994fc2d26e297ac56b4b1522a8bc7fa71c43b14cd1b1fe6c5116f7dc
ARG GOLANG_IMAGE=golang:1.26.4-trixie@sha256:68b7145ec43d1820b9a56704554b53d1520aa2a15cb5233e374188a31b2a1bce
ARG RUST_IMAGE=rust:1.96.0-slim-trixie@sha256:c37af730be4fd8104cbf9aedbd6ab259e51ca2d5437817a0f8680edf66ac6c28

ARG NAVIDROME_REPOSITORY=https://github.com/TAE-OK-11/navidrome.git
ARG NAVIDROME_REF=master
ARG NAVIDROME_CACHEBUST=4b3c6578ac81

ARG JEMALLOC_VERSION=5.3.1
ARG FFMPEG_VERSION=8.1.2
ARG OPUS_VERSION=1.6.1
ARG LAME_VERSION=3.100
ARG TAGLIB_VERSION=2.3

ARG NAVIDROME_BUILD_CORES=4
ARG FFMPEG_THREADS=auto
ARG GOMEMLIMIT=auto
ARG GOMAXPROCS=auto
ARG GOGC=125
ARG SCANSCHEDULE=0
ARG GOAMD64_VERSION=v3
ARG RUST_TARGET_CPU=znver3

ARG JBS_GOMAXPROCS_MAX=2
ARG JBS_FFMPEG_THREADS_MAX=1
ARG JBS_GOMEMLIMIT_PERCENT=55
ARG JBS_GOMEMLIMIT_MIN_MIB=192
ARG JBS_GOMEMLIMIT_MAX_MIB=4096

ARG CPU_OPTIMIZATION_FLAGS="-O3 -march=znver3 -mtune=znver3 -DNDEBUG -ffunction-sections -fdata-sections -pipe -fno-plt -falign-functions=32"
ARG THIN_LTO_FLAGS="-flto=thin"
ARG FULL_LTO_FLAGS="-flto"
ARG SQLITE_LTO_FLAGS="-flto"
ARG TAGLIB_LTO_FLAGS="-flto"
ARG LLD_FLAGS="-fuse-ld=lld -Wl,-O2 -Wl,--gc-sections -Wl,--as-needed -Wl,-z,relro,-z,now"

ARG SQLITE_EXTRA_CFLAGS="\
-DSQLITE_ENABLE_FTS5 \
-DSQLITE_ENABLE_STAT4 \
-DSQLITE_ENABLE_JSON1 \
-DSQLITE_OMIT_SHARED_CACHE \
-DSQLITE_DEFAULT_WAL_AUTOCHECKPOINT=4096 \
-DSQLITE_DEFAULT_WAL_SYNCHRONOUS=1 \
-DSQLITE_TEMP_STORE=2 \
-DSQLITE_DEFAULT_MMAP_SIZE=134217728 \
-DSQLITE_MAX_MMAP_SIZE=536870912 \
-DSQLITE_DEFAULT_CACHE_SIZE=-65536 \
-DSQLITE_DEFAULT_MEMSTATUS=0 \
-DSQLITE_LIKE_DOESNT_MATCH_BLOBS \
-DSQLITE_USE_ALLOCA"

ARG JEMALLOC_SHA256="3826bc80232f22ed5c4662f3034f799ca316e819103bdc7bb99018a421706f92"
ARG FFMPEG_SHA256="464beb5e7bf0c311e68b45ae2f04e9cc2af88851abb4082231742a74d97b524c"
ARG OPUS_SHA256="6ffcb593207be92584df15b32466ed64bbec99109f007c82205f0194572411a1"
ARG TAGLIB_SHA256="7349f6fd942418bc7009ebe743eb7c9d055f02921ec56fa436ec25007c47fd38"
ARG LAME_SHA256="ddfe36cab873794038ae2c1210557ad34857a4b6bdc515785d1da9e175b1da1e"

# =========================================================
# Source
# =========================================================

FROM ${DEBIAN_IMAGE} AS source

ARG NAVIDROME_REF
ARG NAVIDROME_REPOSITORY
ARG NAVIDROME_CACHEBUST

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
      git \
      ca-certificates && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /src

RUN echo "NAVIDROME_CACHEBUST=${NAVIDROME_CACHEBUST}" >/dev/null && \
    git init . && \
    git remote add origin "${NAVIDROME_REPOSITORY}" && \
    if git ls-remote --exit-code --heads origin "${NAVIDROME_REF}" >/dev/null 2>&1; then \
      git fetch --depth=1 origin "refs/heads/${NAVIDROME_REF}"; \
    elif git ls-remote --exit-code --tags origin "${NAVIDROME_REF}" >/dev/null 2>&1; then \
      git fetch --depth=1 origin "refs/tags/${NAVIDROME_REF}"; \
    else \
      git fetch --depth=1 origin "${NAVIDROME_REF}"; \
    fi && \
    git checkout --detach FETCH_HEAD && \
    git rev-parse --short=12 HEAD > /src/.git_sha && \
    rm -rf .git

# =========================================================
# jemalloc
# =========================================================

FROM ${DEBIAN_IMAGE} AS jemalloc-builder

ARG JEMALLOC_VERSION
ARG JEMALLOC_SHA256
ARG NAVIDROME_BUILD_CORES
ARG CPU_OPTIMIZATION_FLAGS
ARG THIN_LTO_FLAGS

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
      build-essential clang lld llvm \
      autoconf automake libtool \
      bzip2 wget ca-certificates

WORKDIR /build

RUN wget --https-only --tries=3 --max-redirect=3 -qO jemalloc.tar.bz2 \
      "https://github.com/jemalloc/jemalloc/releases/download/${JEMALLOC_VERSION}/jemalloc-${JEMALLOC_VERSION}.tar.bz2" && \
    echo "${JEMALLOC_SHA256}  jemalloc.tar.bz2" | sha256sum -c - && \
    tar -tjf jemalloc.tar.bz2 >/dev/null && \
    mkdir jemalloc && \
    tar -xjf jemalloc.tar.bz2 --strip-components=1 -C jemalloc

WORKDIR /build/jemalloc

RUN CC="clang -fuse-ld=lld" \
    CXX="clang++ -fuse-ld=lld" \
    AR=llvm-ar \
    RANLIB=llvm-ranlib \
    NM=llvm-nm \
    STRIP=llvm-strip \
    CFLAGS="${CPU_OPTIMIZATION_FLAGS} ${THIN_LTO_FLAGS}" \
    CXXFLAGS="${CPU_OPTIMIZATION_FLAGS} ${THIN_LTO_FLAGS}" \
    LDFLAGS="${THIN_LTO_FLAGS} -Wl,-O2 -Wl,--gc-sections -Wl,--as-needed -Wl,-z,relro,-z,now" \
    ./configure \
      --prefix=/usr/local \
      --disable-cxx \
      --disable-stats \
      --with-malloc-conf="background_thread:true,metadata_thp:disabled,narenas:2,dirty_decay_ms:5000,muzzy_decay_ms:10000,oversize_threshold:8388608,retain:false" && \
    make -j"${NAVIDROME_BUILD_CORES}" install && \
    find /usr/local/lib -name "libjemalloc.so.*" ! -type l -exec strip --strip-unneeded {} +

# =========================================================
# libopus static
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
      build-essential clang lld llvm \
      pkg-config autoconf automake libtool \
      wget ca-certificates

WORKDIR /build

RUN wget --https-only --tries=3 --max-redirect=3 -qO opus.tar.gz \
      "https://downloads.xiph.org/releases/opus/opus-${OPUS_VERSION}.tar.gz" && \
    echo "${OPUS_SHA256}  opus.tar.gz" | sha256sum -c - && \
    tar -tzf opus.tar.gz >/dev/null && \
    mkdir opus && \
    tar -xzf opus.tar.gz --strip-components=1 -C opus

WORKDIR /build/opus

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
      --disable-shared \
      --enable-static \
      --disable-extra-programs \
      --disable-doc && \
    make -j"${NAVIDROME_BUILD_CORES}" install && \
    llvm-ranlib /usr/local/lib/libopus.a

# =========================================================
# LAME MP3 encoder static
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
      build-essential clang lld llvm \
      pkg-config autoconf automake libtool \
      wget ca-certificates nasm

WORKDIR /build

RUN wget --https-only --tries=3 --max-redirect=3 -qO lame.tar.gz \
      "https://downloads.sourceforge.net/project/lame/lame/${LAME_VERSION}/lame-${LAME_VERSION}.tar.gz" && \
    echo "${LAME_SHA256}  lame.tar.gz" | sha256sum -c - && \
    tar -tzf lame.tar.gz >/dev/null && \
    mkdir lame && \
    tar -xzf lame.tar.gz --strip-components=1 -C lame

WORKDIR /build/lame

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
      --disable-shared \
      --enable-static \
      --disable-frontend \
      --disable-decoder \
      --disable-analyzer-hooks && \
    make -j"${NAVIDROME_BUILD_CORES}" install && \
    mkdir -p /usr/local/lib/pkgconfig && \
    printf '%s\n' \
      'prefix=/usr/local' \
      'exec_prefix=${prefix}' \
      'libdir=${exec_prefix}/lib' \
      'includedir=${prefix}/include' \
      '' \
      'Name: libmp3lame' \
      'Description: LAME MP3 encoder library' \
      "Version: ${LAME_VERSION}" \
      'Libs: -L${libdir} -lmp3lame -lm' \
      'Cflags: -I${includedir}' \
      > /usr/local/lib/pkgconfig/libmp3lame.pc && \
    PKG_CONFIG_PATH=/usr/local/lib/pkgconfig pkg-config --modversion libmp3lame && \
    llvm-ranlib /usr/local/lib/libmp3lame.a

# =========================================================
# FFmpeg: Opus / MP3 specialized
# =========================================================

FROM ${DEBIAN_IMAGE} AS ffmpeg-builder

ARG FFMPEG_VERSION
ARG FFMPEG_SHA256
ARG NAVIDROME_BUILD_CORES
ARG CPU_OPTIMIZATION_FLAGS
ARG FULL_LTO_FLAGS
ARG LLD_FLAGS

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
      build-essential clang lld llvm \
      pkg-config yasm nasm \
      wget ca-certificates xz-utils file

COPY --from=opus-builder /usr/local/lib/libopus.a /usr/local/lib/
COPY --from=opus-builder /usr/local/lib/pkgconfig/opus.pc /usr/local/lib/pkgconfig/
COPY --from=opus-builder /usr/local/include/opus /usr/local/include/opus

COPY --from=lame-builder /usr/local/lib/libmp3lame.a /usr/local/lib/
COPY --from=lame-builder /usr/local/lib/pkgconfig/libmp3lame.pc /usr/local/lib/pkgconfig/
COPY --from=lame-builder /usr/local/include/lame /usr/local/include/lame

ENV PKG_CONFIG_PATH=/usr/local/lib/pkgconfig:/usr/lib/pkgconfig:/usr/share/pkgconfig

RUN echo "/usr/local/lib" > /etc/ld.so.conf.d/local.conf && \
    ldconfig && \
    pkg-config --modversion opus && \
    pkg-config --modversion libmp3lame && \
    pkg-config --libs --static opus && \
    pkg-config --libs --static libmp3lame && \
    test -f /usr/local/include/lame/lame.h && \
    test -e /usr/local/lib/libopus.a && \
    test -e /usr/local/lib/libmp3lame.a

WORKDIR /build

RUN wget --https-only --tries=3 --max-redirect=3 -qO ffmpeg.tar.xz \
      "https://ffmpeg.org/releases/ffmpeg-${FFMPEG_VERSION}.tar.xz" && \
    echo "${FFMPEG_SHA256}  ffmpeg.tar.xz" | sha256sum -c - && \
    tar -tJf ffmpeg.tar.xz >/dev/null && \
    mkdir ffmpeg && \
    tar -xJf ffmpeg.tar.xz --strip-components=1 -C ffmpeg

WORKDIR /build/ffmpeg

RUN ./configure \
      --cc=clang \
      --cxx=clang++ \
      --ar=llvm-ar \
      --ranlib=llvm-ranlib \
      --nm=llvm-nm \
      --pkg-config=pkg-config \
      --pkg-config-flags=--static \
      --target-os=linux \
      --arch=x86_64 \
      --cpu=znver3 \
      --disable-runtime-cpudetect \
      --enable-hardcoded-tables \
      --disable-autodetect \
      --disable-network \
      --disable-debug \
      --disable-doc \
      --disable-ffplay \
      --enable-ffprobe \
      --disable-everything \
      --extra-cflags="-I/usr/local/include ${CPU_OPTIMIZATION_FLAGS} ${FULL_LTO_FLAGS}" \
      --extra-ldflags="-L/usr/local/lib ${FULL_LTO_FLAGS} ${LLD_FLAGS}" \
      --enable-avcodec \
      --enable-avformat \
      --enable-avfilter \
      --enable-swresample \
      --enable-protocol=file,pipe \
      --enable-demuxer=mov,mp3,aac,flac,wav,aiff,ogg \
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
# Rust unified helper
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

RUN mkdir -p src

RUN cat > Cargo.toml <<'TOML'
[package]
name = "jbs-helper"
version = "0.1.0"
edition = "2021"

[dependencies]
rusqlite = { version = "=0.40.1", features = ["bundled"] }
walkdir = "=2.5.0"

[profile.release]
opt-level = 3
lto = "fat"
codegen-units = 1
strip = true
panic = "abort"
TOML

RUN cat > src/main.rs <<'RUST'
use std::env;
use std::fs::File;
use std::io::{Read, Write};
use std::net::{SocketAddr, TcpStream};
use std::path::Path;
use std::process::Command;
use std::time::Duration;

use rusqlite::{Connection, OpenFlags};
use walkdir::WalkDir;

const CHUNK: usize = 1024 * 1024;

fn basename(path: &str) -> &str {
    path.rsplit('/').next().unwrap_or(path)
}

fn is_cmd(name: &str, needle: &str) -> bool {
    name == needle || name.ends_with(needle)
}

fn run_healthcheck() -> i32 {
    let port: u16 = env::var("ND_PORT")
        .unwrap_or_default()
        .parse()
        .unwrap_or(4533);

    let addr = SocketAddr::from(([127, 0, 0, 1], port));
    let timeout = Duration::from_secs(4);

    let mut stream = match TcpStream::connect_timeout(&addr, timeout) {
        Ok(s) => s,
        Err(_) => return 1,
    };

    let _ = stream.set_read_timeout(Some(timeout));
    let _ = stream.set_write_timeout(Some(timeout));

    let req = format!(
        "GET /ping HTTP/1.0\r\nHost: 127.0.0.1:{port}\r\nConnection: close\r\n\r\n"
    );

    if stream.write_all(req.as_bytes()).is_err() {
        return 1;
    }

    let mut buf = [0u8; 512];
    let n = stream.read(&mut buf).unwrap_or(0);
    let resp = std::str::from_utf8(&buf[..n]).unwrap_or("");

    if resp.starts_with("HTTP/1.") && resp.contains(" 200 ") {
        0
    } else {
        1
    }
}

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

fn run_sqlite_maint(args: &[String]) -> i32 {
    let mode = args.first().map(String::as_str).unwrap_or("startup");

    match mode {
        "startup" => run_sql(
            "startup",
            "
            PRAGMA journal_mode=WAL;
            PRAGMA synchronous=NORMAL;
            PRAGMA foreign_keys=ON;
            PRAGMA temp_store=MEMORY;
            PRAGMA mmap_size=134217728;
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
    }
}

fn parse_limit_mb(args: &[String]) -> u64 {
    let mut i = 0;

    while i < args.len() {
        if args[i] == "--limit-mb" {
            if let Some(v) = args.get(i + 1) {
                return v.parse::<u64>().unwrap_or(32);
            }
        }
        i += 1;
    }

    env::var("JBS_CACHE_WARM_LIMIT_MB")
        .ok()
        .and_then(|v| v.parse::<u64>().ok())
        .unwrap_or(32)
}

fn read_some(path: &Path, remaining: &mut u64, buf: &mut [u8]) {
    if *remaining == 0 {
        return;
    }

    let Ok(mut f) = File::open(path) else {
        return;
    };

    loop {
        if *remaining == 0 {
            break;
        }

        let want = (*remaining).min(buf.len() as u64) as usize;

        match f.read(&mut buf[..want]) {
            Ok(0) => break,
            Ok(n) => *remaining = remaining.saturating_sub(n as u64),
            Err(_) => break,
        }
    }

    eprintln!("[cache-warm] warmed {}", path.display());
}

fn warm_fixed_db_files(data: &str, remaining: &mut u64, buf: &mut [u8]) {
    let files = [
        format!("{data}/navidrome.db"),
        format!("{data}/navidrome.db-wal"),
        format!("{data}/navidrome.db-shm"),
    ];

    for file in files {
        if *remaining == 0 {
            break;
        }

        read_some(Path::new(&file), remaining, buf);
    }
}

fn run_cache_warm(args: &[String]) -> i32 {
    let mut remaining = parse_limit_mb(args).saturating_mul(1024 * 1024);

    if remaining == 0 {
        return 0;
    }

    let data = env::var("ND_DATAFOLDER").unwrap_or_else(|_| "/data".to_string());
    let cache = env::var("ND_CACHEFOLDER").unwrap_or_else(|_| "/cache".to_string());
    let mut buf = vec![0u8; CHUNK];

    warm_fixed_db_files(&data, &mut remaining, &mut buf);

    let mut seen = 0usize;

    for entry in WalkDir::new(cache)
        .max_depth(3)
        .follow_links(false)
        .into_iter()
        .filter_map(Result::ok)
    {
        if remaining == 0 || seen >= 128 {
            break;
        }

        if entry.file_type().is_file() {
            read_some(entry.path(), &mut remaining, &mut buf);
            seen += 1;
        }
    }

    eprintln!("[cache-warm] done");
    0
}

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

fn capture_ffmpeg(args: &[&str]) -> Result<String, String> {
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

fn run_ffmpeg_preflight(args: &[String]) -> i32 {
    let strict = args.iter().any(|a| a == "--strict");
    let path = ffmpeg_path();

    let codecs = capture_ffmpeg(&["-hide_banner", "-codecs"]).unwrap_or_default();
    let formats = capture_ffmpeg(&["-hide_banner", "-formats"]).unwrap_or_default();
    let filters = capture_ffmpeg(&["-hide_banner", "-filters"]).unwrap_or_default();

    let mut failures = Vec::new();

    for needle in ["libopus", "libmp3lame", "alac", "aac", "mp3", "flac", "opus"] {
        require(&codecs, needle, &mut failures);
    }

    for needle in ["mov", "mp3", "flac", "wav", "ogg", "opus"] {
        require(&formats, needle, &mut failures);
    }

    for needle in ["aresample", "aformat"] {
        require(&filters, needle, &mut failures);
    }

    if failures.is_empty() {
        eprintln!("[ffmpeg-preflight] ok: {path}");
        return 0;
    }

    eprintln!(
        "[ffmpeg-preflight] missing capabilities from {path}: {}",
        failures.join(", ")
    );

    if strict { 1 } else { 0 }
}

fn print_usage() -> i32 {
    eprintln!(
        "usage: jbs-helper [healthcheck|sqlite-maint|cache-warm|ffmpeg-preflight] [args...]"
    );
    2
}

fn main() {
    let mut args: Vec<String> = env::args().collect();
    let argv0 = args.first().cloned().unwrap_or_else(|| "jbs-helper".to_string());
    let name = basename(&argv0).to_string();

    let code = if is_cmd(&name, "healthcheck") {
        run_healthcheck()
    } else if is_cmd(&name, "jbs-sqlite-maint") {
        let sub_args = args.split_off(1);
        run_sqlite_maint(&sub_args)
    } else if is_cmd(&name, "jbs-cache-warm") {
        let sub_args = args.split_off(1);
        run_cache_warm(&sub_args)
    } else if is_cmd(&name, "jbs-ffmpeg-preflight") {
        let sub_args = args.split_off(1);
        run_ffmpeg_preflight(&sub_args)
    } else {
        let Some(cmd) = args.get(1).cloned() else {
            std::process::exit(print_usage());
        };

        let sub_args: Vec<String> = args.into_iter().skip(2).collect();

        match cmd.as_str() {
            "healthcheck" => run_healthcheck(),
            "sqlite-maint" => run_sqlite_maint(&sub_args),
            "cache-warm" => run_cache_warm(&sub_args),
            "ffmpeg-preflight" => run_ffmpeg_preflight(&sub_args),
            _ => print_usage(),
        }
    };

    std::process::exit(code);
}
RUST

RUN --mount=type=cache,target=/usr/local/cargo/registry \
    --mount=type=cache,target=/usr/local/cargo/git \
    --mount=type=cache,target=/build/target \
    CARGO_TARGET_X86_64_UNKNOWN_LINUX_MUSL_LINKER=musl-gcc \
    CC_x86_64_unknown_linux_musl=musl-gcc \
    RUSTFLAGS="-C target-cpu=${RUST_TARGET_CPU} -C target-feature=+crt-static -C opt-level=3 -C lto=fat -C codegen-units=1" \
    cargo build --release --target x86_64-unknown-linux-musl -j"${NAVIDROME_BUILD_CORES}" && \
    mkdir -p /out && \
    cp target/x86_64-unknown-linux-musl/release/jbs-helper /out/jbs-helper

# =========================================================
# UI build
# =========================================================

FROM ${NODE_IMAGE} AS jsbuilder

WORKDIR /src/ui

ENV NODE_OPTIONS=--max-old-space-size=3072

COPY --link --from=source /src/ui/package.json /src/ui/package-lock.json ./
COPY --link --from=source /src/ui/bin/ ./bin/

RUN --mount=type=cache,target=/root/.npm \
    test -s ./bin/update-workbox.sh && \
    sed -i 's/\r$//' ./bin/update-workbox.sh && \
    chmod 755 ./bin/update-workbox.sh && \
    ls -la ./bin && \
    npm ci --prefer-offline --no-audit --fund=false

COPY --link --from=source /src/ui ./

RUN --mount=type=cache,target=/root/.npm \
    npm run build && \
    test -s ./build/index.html && \
    br_count="$(find ./build -type f -name '*.br' | wc -l)" && \
    gz_count="$(find ./build -type f -name '*.gz' | wc -l)" && \
    test "${br_count}" -gt 0 && \
    test "${gz_count}" -gt 0 && \
    js_bundle="$(find ./build/assets -type f -name 'index-*.js' -print -quit)" && \
    test -n "${js_bundle}" && \
    test -s "${js_bundle}.br" && \
    test -s "${js_bundle}.gz" && \
    css_bundle="$(find ./build/assets -type f -name 'index-*.css' -print -quit)" && \
    test -n "${css_bundle}" && \
    test -s "${css_bundle}.br" && \
    test -s "${css_bundle}.gz" && \
    printf '[jsbuilder] precompressed UI assets: br=%s gz=%s\n' "${br_count}" "${gz_count}"

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
ARG TAGLIB_LTO_FLAGS
ARG SQLITE_LTO_FLAGS
ARG LLD_FLAGS
ARG GOAMD64_VERSION
ARG SQLITE_EXTRA_CFLAGS

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
      clang lld llvm make cmake \
      zlib1g-dev ca-certificates pkg-config \
      wget libutfcpp-dev file

WORKDIR /taglib-build

RUN wget --https-only --tries=3 --max-redirect=3 -qO taglib.tar.gz \
      "https://github.com/taglib/taglib/releases/download/v${TAGLIB_VERSION}/taglib-${TAGLIB_VERSION}.tar.gz" && \
    echo "${TAGLIB_SHA256}  taglib.tar.gz" | sha256sum -c - && \
    tar -tzf taglib.tar.gz >/dev/null && \
    tar -xzf taglib.tar.gz && \
    cd "taglib-${TAGLIB_VERSION}" && \
    cmake -DCMAKE_BUILD_TYPE=Release \
      -DBUILD_SHARED_LIBS=OFF \
      -DBUILD_TESTING=OFF \
      -DBUILD_EXAMPLES=OFF \
      -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=ON \
      -DTAGLIB_BUILD_EXAMPLES=OFF \
      -DTAGLIB_BUILD_TESTS=OFF \
      -DCMAKE_C_COMPILER=clang \
      -DCMAKE_CXX_COMPILER=clang++ \
      -DCMAKE_AR=llvm-ar \
      -DCMAKE_RANLIB=llvm-ranlib \
      -DCMAKE_C_FLAGS="${CPU_OPTIMIZATION_FLAGS} ${TAGLIB_LTO_FLAGS} -fPIC" \
      -DCMAKE_CXX_FLAGS="${CPU_OPTIMIZATION_FLAGS} ${TAGLIB_LTO_FLAGS} -fPIC" \
      -DCMAKE_EXE_LINKER_FLAGS="${TAGLIB_LTO_FLAGS} ${LLD_FLAGS}" \
      -DCMAKE_SHARED_LINKER_FLAGS="${TAGLIB_LTO_FLAGS} ${LLD_FLAGS}" \
      -DCMAKE_INSTALL_PREFIX=/usr/local . && \
    make -j"${NAVIDROME_BUILD_CORES}" install

WORKDIR /src

COPY --from=source /src/go.mod /src/go.sum ./

RUN --mount=type=cache,target=/go/pkg/mod \
    go mod download

COPY --from=source /src ./
COPY --link --from=jsbuilder /src/ui/build ./ui/build/

RUN test -s ./ui/build/index.html && \
    test -n "$(find ./ui/build -type f -name '*.br' -print -quit)" && \
    test -n "$(find ./ui/build -type f -name '*.gz' -print -quit)" && \
    printf '[gobuilder] embedded UI precompressed assets: br=%s gz=%s\n' \
      "$(find ./ui/build -type f -name '*.br' | wc -l)" \
      "$(find ./ui/build -type f -name '*.gz' | wc -l)"

ENV GOAMD64=${GOAMD64_VERSION} \
    CGO_ENABLED=1 \
    PKG_CONFIG_PATH=/usr/local/lib/pkgconfig \
    CC=clang \
    CXX=clang++ \
    CGO_CFLAGS="${CPU_OPTIMIZATION_FLAGS} ${SQLITE_LTO_FLAGS} ${SQLITE_EXTRA_CFLAGS}" \
    CGO_CXXFLAGS="${CPU_OPTIMIZATION_FLAGS} ${SQLITE_LTO_FLAGS}" \
    CGO_LDFLAGS="${SQLITE_LTO_FLAGS} ${LLD_FLAGS} -L/usr/local/lib -lstdc++ -lz -lm"

RUN --mount=type=cache,target=/root/.cache/go-build \
    --mount=type=cache,target=/go/pkg/mod \
    GIT_SHA="$(cat /src/.git_sha 2>/dev/null || echo dev)" && \
    EXTLDFLAGS="${SQLITE_LTO_FLAGS} ${LLD_FLAGS}" && \
    mkdir -p /out && \
    GOOS=linux GOARCH=amd64 go build \
      -trimpath \
      -buildvcs=false \
      -tags="netgo osusergo sqlite_fts5 sqlite_foreign_keys sqlite_stat4 sqlite_json embed" \
      -ldflags="-linkmode=external -extld=clang -extldflags '${EXTLDFLAGS}' -s -w -buildid= -X github.com/navidrome/navidrome/consts.gitSha=${GIT_SHA} -X github.com/navidrome/navidrome/consts.gitTag=${NAVIDROME_REF}-${GIT_SHA}" \
      -o /out/navidrome . && \
    file /out/navidrome

# =========================================================
# Timezone data
# =========================================================

FROM ${DEBIAN_IMAGE} AS tzdata-extract

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends tzdata

# =========================================================
# Runtime
# =========================================================

FROM ${DEBIAN_IMAGE} AS release

LABEL org.opencontainers.image.authors="JBS Networks" \
      org.opencontainers.image.title="JBS Navidrome Ultra 6.1 Slim v9 Light Final" \
      org.opencontainers.image.description="AMD EPYC Zen3 optimized Navidrome with static Opus/MP3, jemalloc light profile, Rust helpers" \
      org.opencontainers.image.source="https://github.com/navidrome/navidrome" \
      org.opencontainers.image.vendor="JBS Networks" \
      jbs.optimization="JBS-Navidrome-Ultra-6.1-Slim-v9/AMD-EPYC-Zen3/Opus-MP3-static/FullLTO-FFmpeg/SQLite-Light/Jemalloc-Light/RustFatLTO-musl-static/Resource-Aware"

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates zlib1g libstdc++6 libwebp7 libwebpdemux2 && \
    rm -rf \
      /var/lib/apt/lists/* \
      /usr/share/doc /usr/share/man /usr/share/info \
      /usr/share/lintian /usr/share/linda \
      /usr/share/common-licenses /usr/share/locale

RUN mkdir -p /usr/share/zoneinfo/Asia

COPY --link --from=tzdata-extract /usr/share/zoneinfo/Asia/Seoul /usr/share/zoneinfo/Asia/Seoul

RUN ln -snf /usr/share/zoneinfo/Asia/Seoul /etc/localtime && \
    echo "Asia/Seoul" > /etc/timezone

COPY --link --from=ffmpeg-builder /usr/local/bin/ffmpeg /usr/local/bin/ffmpeg.real
COPY --link --from=ffmpeg-builder /usr/local/bin/ffprobe /usr/local/bin/ffprobe
COPY --link --from=jemalloc-builder /usr/local/lib/libjemalloc.so.2 /usr/local/lib/

RUN echo "/usr/local/lib" > /etc/ld.so.conf.d/local.conf && \
    ldconfig && \
    for lib in webp webpdemux; do \
      target=""; \
      for cand in /usr/lib/*/lib${lib}.so.* /lib/*/lib${lib}.so.*; do \
        [ -e "$cand" ] || continue; \
        target="$cand"; \
      done; \
      [ -n "$target" ] || { echo "missing native lib${lib}" >&2; exit 1; }; \
      ln -sf "$target" "/usr/local/lib/lib${lib}.so"; \
    done && \
    ldconfig

RUN cat > /usr/local/bin/ffmpeg <<'SH'
#!/bin/sh
THREADS=$(printf '%d' "${FFMPEG_THREADS:-1}" 2>/dev/null)
if [ -z "$THREADS" ] || [ "$THREADS" -lt 1 ] 2>/dev/null; then
    THREADS=1
fi
exec /usr/local/bin/ffmpeg.real \
    -nostdin -hide_banner -nostats -loglevel warning \
    -threads "$THREADS" -filter_threads "$THREADS" "$@"
SH

RUN chmod 755 /usr/local/bin/ffmpeg

RUN printf '%s\n' 'navidrome:x:1000:1000:Navidrome:/nonexistent:/usr/sbin/nologin' >> /etc/passwd && \
    printf '%s\n' 'navidrome:x:1000:' >> /etc/group && \
    install -d -o 1000 -g 1000 -m 755 /app /data /music /cache /cache/tmp && \
    touch /.nddockerenv

COPY --link --chown=1000:1000 --chmod=750 --from=gobuilder /out/navidrome /app/navidrome
COPY --link --chmod=755 --from=rust-builder /out/jbs-helper /usr/local/bin/jbs-helper

RUN ln -s /usr/local/bin/jbs-helper /usr/local/bin/healthcheck && \
    ln -s /usr/local/bin/jbs-helper /usr/local/bin/jbs-sqlite-maint && \
    ln -s /usr/local/bin/jbs-helper /usr/local/bin/jbs-cache-warm && \
    ln -s /usr/local/bin/jbs-helper /usr/local/bin/jbs-ffmpeg-preflight

RUN test -x /app/navidrome && \
    test -x /usr/local/bin/ffmpeg.real && \
    test -x /usr/local/bin/ffprobe && \
    test -x /usr/local/bin/jbs-helper && \
    test -L /usr/local/bin/healthcheck && \
    test -L /usr/local/bin/jbs-sqlite-maint && \
    test -L /usr/local/bin/jbs-cache-warm && \
    test -L /usr/local/bin/jbs-ffmpeg-preflight && \
    libs="$(ldconfig -p)" && \
    case "$libs" in *libjemalloc.so.2*) : ;; *) echo "missing libjemalloc.so.2" >&2; exit 1 ;; esac && \
    ffdeps="$(ldd /usr/local/bin/ffmpeg.real 2>/dev/null || true)" && \
    case "$ffdeps" in \
      *libopus.so*|*libmp3lame.so*) \
        echo "ffmpeg is dynamically linked against libopus/libmp3lame; expected static link" >&2; \
        echo "$ffdeps" >&2; exit 1 ;; \
      *) : ;; \
    esac

RUN cat > /entrypoint <<'SH'
#!/bin/sh
set -eu

is_true() { case "${1:-}" in 1|true|TRUE|True|yes|YES|Yes|on|ON|On) return 0 ;; *) return 1 ;; esac; }
contains() { case "$1" in *"$2"*) return 0 ;; *) return 1 ;; esac; }
is_auto() { case "${1:-}" in ""|auto|AUTO|Auto) return 0 ;; *) return 1 ;; esac; }
valid_uint() { case "${1:-}" in ""|*[!0-9]*) return 1 ;; *) return 0 ;; esac; }

detect_cpu_cores() {
    if [ -r /sys/fs/cgroup/cpu.max ]; then
        read -r quota period < /sys/fs/cgroup/cpu.max || true
        if valid_uint "${quota:-}" && valid_uint "${period:-}" && [ "$period" -gt 0 ] 2>/dev/null; then
            cores=$(( (quota + period - 1) / period ))
            [ "$cores" -lt 1 ] && cores=1
            echo "$cores"
            return 0
        fi
    fi

    cores="$(nproc 2>/dev/null || true)"
    if ! valid_uint "$cores" || [ "$cores" -lt 1 ] 2>/dev/null; then
        cores=1
    fi
    echo "$cores"
}

detect_memory_mib() {
    if [ -r /sys/fs/cgroup/memory.max ]; then
        read -r max < /sys/fs/cgroup/memory.max || true
        case "${max:-}" in
            ""|max|*[!0-9]*)
                ;;
            *)
                if [ "$max" -gt 0 ] 2>/dev/null && [ "$max" -lt 9223372036854771712 ] 2>/dev/null; then
                    echo $(( max / 1048576 ))
                    return 0
                fi
                ;;
        esac
    fi

    while IFS=' ' read -r key value unit; do
        case "$key" in
            MemTotal:)
                if valid_uint "$value"; then
                    echo $(( value / 1024 ))
                    return 0
                fi
                ;;
        esac
    done < /proc/meminfo

    echo 0
}

cap_uint() {
    value="$1"
    min="$2"
    max="$3"

    if ! valid_uint "$value"; then
        value="$min"
    fi

    if [ "$value" -lt "$min" ] 2>/dev/null; then
        value="$min"
    fi

    if valid_uint "$max" && [ "$max" -gt 0 ] 2>/dev/null && [ "$value" -gt "$max" ] 2>/dev/null; then
        value="$max"
    fi

    echo "$value"
}

autotune_resources() {
    if ! is_true "${JBS_AUTOTUNE:-true}"; then
        return 0
    fi

    cores="$(detect_cpu_cores)"
    mem_mib="$(detect_memory_mib)"

    if ! valid_uint "$cores" || [ "$cores" -lt 1 ] 2>/dev/null; then
        cores=1
    fi

    if ! valid_uint "$mem_mib"; then
        mem_mib=0
    fi

    if is_auto "${GOMAXPROCS:-}"; then
        max="${JBS_GOMAXPROCS_MAX:-2}"
        if ! valid_uint "$max" || [ "$max" -lt 1 ] 2>/dev/null; then
            max=2
        fi
        export GOMAXPROCS="$(cap_uint "$cores" 1 "$max")"
    fi

    if is_auto "${FFMPEG_THREADS:-}"; then
        max="${JBS_FFMPEG_THREADS_MAX:-1}"
        if ! valid_uint "$max" || [ "$max" -lt 1 ] 2>/dev/null; then
            max=1
        fi
        tuned_ffmpeg=$(( cores / 2 ))
        [ "$tuned_ffmpeg" -lt 1 ] && tuned_ffmpeg=1
        export FFMPEG_THREADS="$(cap_uint "$tuned_ffmpeg" 1 "$max")"
    fi

    gmem_limit="${GOMEMLIMIT:-${JBS_GOMEMLIMIT:-}}"
    if is_auto "$gmem_limit"; then
        percent="${JBS_GOMEMLIMIT_PERCENT:-55}"
        min_mib="${JBS_GOMEMLIMIT_MIN_MIB:-192}"
        max_mib="${JBS_GOMEMLIMIT_MAX_MIB:-4096}"

        if ! valid_uint "$percent" || [ "$percent" -lt 10 ] 2>/dev/null || [ "$percent" -gt 95 ] 2>/dev/null; then
            percent=55
        fi

        if ! valid_uint "$min_mib" || [ "$min_mib" -lt 64 ] 2>/dev/null; then
            min_mib=192
        fi

        if ! valid_uint "$max_mib" || [ "$max_mib" -lt "$min_mib" ] 2>/dev/null; then
            max_mib=4096
        fi

        if [ "$mem_mib" -gt 0 ] 2>/dev/null; then
            tuned_mem=$(( mem_mib * percent / 100 ))
        else
            tuned_mem="$max_mib"
        fi

        export GOMEMLIMIT="$(cap_uint "$tuned_mem" "$min_mib" "$max_mib")MiB"
    else
        export GOMEMLIMIT="$gmem_limit"
    fi

    if is_auto "${JBS_CACHE_WARM_LIMIT_MB:-}"; then
        if [ "$mem_mib" -le 0 ] 2>/dev/null; then
            warm=32
        elif [ "$mem_mib" -le 1024 ] 2>/dev/null; then
            warm=0
        elif [ "$mem_mib" -le 2048 ] 2>/dev/null; then
            warm=64
        elif [ "$mem_mib" -le 4096 ] 2>/dev/null; then
            warm=128
        else
            warm=256
        fi
        export JBS_CACHE_WARM_LIMIT_MB="$warm"
    fi

    if is_auto "${ND_DEVSCANNERTHREADS:-}"; then
        scanner_threads="${GOMAXPROCS:-1}"
        if ! valid_uint "$scanner_threads" || [ "$scanner_threads" -lt 1 ] 2>/dev/null; then
            scanner_threads=1
        fi
        if [ "$mem_mib" -gt 768 ] 2>/dev/null && [ "$scanner_threads" -lt 4 ] 2>/dev/null; then
            scanner_threads=4
        fi
        export ND_DEVSCANNERTHREADS="$scanner_threads"
    fi

    echo "[entrypoint] autotune: cores=${cores} mem=${mem_mib}MiB GOMAXPROCS=${GOMAXPROCS:-unset} GOMEMLIMIT=${GOMEMLIMIT:-unset} FFMPEG_THREADS=${FFMPEG_THREADS:-unset} SCANNER_THREADS=${ND_DEVSCANNERTHREADS:-unset} CACHE_WARM=${JBS_CACHE_WARM_LIMIT_MB:-unset}MB" >&2
}

check_database_writable() {
    data_dir="${ND_DATAFOLDER:-/data}"
    if [ -z "$data_dir" ]; then
        data_dir=/data
    fi

    if [ ! -d "$data_dir" ]; then
        echo "[entrypoint] fatal: data directory does not exist: $data_dir" >&2
        exit 1
    fi

    if [ ! -w "$data_dir" ]; then
        echo "[entrypoint] fatal: data directory is not writable by uid=$(id -u): $data_dir" >&2
        exit 1
    fi

    tmp="${data_dir}/.jbs-write-test.$$"
    if ! ( : > "$tmp" ) 2>/dev/null; then
        echo "[entrypoint] fatal: cannot create files in data directory: $data_dir" >&2
        exit 1
    fi
    rm -f "$tmp"

    db_path="${ND_DBPATH:-${data_dir}/navidrome.db}"
    case "$db_path" in
        file:*)
            db_path="${db_path#file:}"
            db_path="${db_path%%\?*}"
            ;;
        *:memory:*|"")
            db_path=""
            ;;
    esac

    if [ -n "$db_path" ] && [ -e "$db_path" ] && [ ! -w "$db_path" ]; then
        echo "[entrypoint] fatal: database file is not writable by uid=$(id -u): $db_path" >&2
        exit 1
    fi
}

run_optional() {
    enabled="$1"
    shift

    if ! is_true "$enabled"; then
        return 0
    fi

    set +e
    "$@"
    code="$?"
    set -e

    if [ "$code" -eq 126 ] || [ "$code" -eq 127 ]; then
        echo "[entrypoint] optional helper unavailable: $* status=${code}; skipping" >&2
        return 0
    fi

    if [ "$code" -ne 0 ]; then
        echo "[entrypoint] optional helper failed: $* status=${code}; continuing" >&2
    fi

    return 0
}

run_required() {
    enabled="$1"
    shift

    if ! is_true "$enabled"; then
        return 0
    fi

    set +e
    "$@"
    code="$?"
    set -e

    if [ "$code" -ne 0 ]; then
        echo "[entrypoint] required helper failed: $* status=${code}" >&2
        exit "$code"
    fi

    return 0
}

configure_allocator() {
    unset LD_PRELOAD

    if ! is_true "${JBS_USE_JEMALLOC:-true}"; then
        echo "[entrypoint] jemalloc disabled by JBS_USE_JEMALLOC=false" >&2
        return 0
    fi

    if [ ! -r /usr/local/lib/libjemalloc.so.2 ]; then
        echo "[entrypoint] jemalloc not found; using system allocator" >&2
        return 0
    fi

    set +e
    LD_PRELOAD=/usr/local/lib/libjemalloc.so.2 /bin/true >/dev/null 2>&1
    code="$?"
    set -e

    if [ "$code" -ne 0 ]; then
        echo "[entrypoint] jemalloc preload test failed status=${code}; using system allocator" >&2
        unset LD_PRELOAD
        return 0
    fi

    export LD_PRELOAD=/usr/local/lib/libjemalloc.so.2
    echo "[entrypoint] jemalloc enabled" >&2
}

ffmpeg_fallback_preflight() {
    if [ ! -x /usr/local/bin/ffmpeg.real ]; then
        echo "[entrypoint] ffmpeg.real missing or not executable" >&2
        return 1
    fi

    codecs="$(/usr/local/bin/ffmpeg.real -hide_banner -codecs 2>&1 || true)"

    for n in libopus libmp3lame alac mp3; do
        contains "$codecs" "$n" || {
            echo "[entrypoint] missing ffmpeg codec: $n" >&2
            return 1
        }
    done

    echo "[entrypoint] ffmpeg fallback preflight ok" >&2
    return 0
}

autotune_resources
check_database_writable

if is_true "${JBS_FFMPEG_PREFLIGHT:-true}"; then
    if [ -x /usr/local/bin/jbs-ffmpeg-preflight ]; then
        set +e
        /usr/local/bin/jbs-ffmpeg-preflight --strict
        code="$?"
        set -e

        if [ "$code" -eq 0 ]; then
            :
        elif [ "$code" -eq 126 ] || [ "$code" -eq 127 ]; then
            echo "[entrypoint] jbs-ffmpeg-preflight unavailable; using ffmpeg.real fallback status=${code}" >&2
            run_required "true" ffmpeg_fallback_preflight
        else
            echo "[entrypoint] required helper failed: jbs-ffmpeg-preflight --strict status=${code}" >&2
            exit "$code"
        fi
    else
        echo "[entrypoint] jbs-ffmpeg-preflight missing; using ffmpeg.real fallback" >&2
        run_required "true" ffmpeg_fallback_preflight
    fi
fi

if [ -x /usr/local/bin/jbs-sqlite-maint ]; then
    run_optional "${JBS_SQLITE_MAINT:-true}" /usr/local/bin/jbs-sqlite-maint startup
else
    echo "[entrypoint] jbs-sqlite-maint missing; skipping sqlite startup maintenance" >&2
fi

if is_true "${JBS_CACHE_WARM:-false}"; then
    if [ -x /usr/local/bin/jbs-cache-warm ]; then
        run_optional "true" /usr/local/bin/jbs-cache-warm --limit-mb "${JBS_CACHE_WARM_LIMIT_MB:-32}"
    else
        echo "[entrypoint] jbs-cache-warm missing; skipping cache warm" >&2
    fi
fi

configure_allocator

exec /app/navidrome "$@"
SH

RUN chmod 755 /entrypoint && /bin/sh -n /entrypoint

USER 1000:1000

VOLUME ["/data", "/music", "/cache"]

ARG GOMEMLIMIT
ARG GOMAXPROCS
ARG GOGC
ARG SCANSCHEDULE
ARG FFMPEG_THREADS
ARG JBS_GOMAXPROCS_MAX
ARG JBS_FFMPEG_THREADS_MAX
ARG JBS_GOMEMLIMIT_PERCENT
ARG JBS_GOMEMLIMIT_MIN_MIB
ARG JBS_GOMEMLIMIT_MAX_MIB

ENV TZ=Asia/Seoul \
    TMPDIR=/cache/tmp \
    MALLOC_CONF="background_thread:true,metadata_thp:disabled,narenas:2,dirty_decay_ms:5000,muzzy_decay_ms:10000,oversize_threshold:8388608,retain:false" \
    GOMAXPROCS=${GOMAXPROCS} \
    GOGC=${GOGC} \
    JBS_GOMEMLIMIT=${GOMEMLIMIT} \
    GODEBUG=netdns=go,madvdontneed=1 \
    FFMPEG_THREADS=${FFMPEG_THREADS} \
    JBS_AUTOTUNE=true \
    JBS_GOMAXPROCS_MAX=${JBS_GOMAXPROCS_MAX} \
    JBS_FFMPEG_THREADS_MAX=${JBS_FFMPEG_THREADS_MAX} \
    JBS_GOMEMLIMIT_PERCENT=${JBS_GOMEMLIMIT_PERCENT} \
    JBS_GOMEMLIMIT_MIN_MIB=${JBS_GOMEMLIMIT_MIN_MIB} \
    JBS_GOMEMLIMIT_MAX_MIB=${JBS_GOMEMLIMIT_MAX_MIB} \
    ND_DEVSCANNERTHREADS=auto \
    ND_ADDRESS=0.0.0.0 \
    ND_PORT=4533 \
    ND_FFMPEGPATH=/usr/local/bin/ffmpeg \
    ND_MUSICFOLDER=/music \
    ND_DATAFOLDER=/data \
    ND_CACHEFOLDER=/cache \
    ND_CONFIGFILE=/data/navidrome.toml \
    ND_DBPATH="file:/data/navidrome.db?mode=rwc&cache=private&_journal_mode=WAL&_synchronous=NORMAL&_locking_mode=NORMAL&_txlock=immediate&_busy_timeout=120000&_foreign_keys=on&_cache_size=-65536&_stmt_cache_size=128&_secure_delete=OFF" \
    ND_DEVOPTIMIZEDB=false \
    ND_ENFORCENONROOTUSER=true \
    ND_SCANNER_ENABLED=true \
    ND_SCANNER_SCHEDULE=${SCANSCHEDULE} \
    ND_SCANNER_SCANONSTARTUP=false \
    ND_SCANNER_WATCHERWAIT=0s \
    ND_SCANNER_PURGEMISSING=never \
    ND_SCANNER_FOLLOWSYMLINKS=false \
    ND_SCANNER_EXTRACTOR=taglib \
    ND_SEARCH_BACKEND=fts \
    ND_SEARCH_FULLSTRING=false \
    ND_SMARTPLAYLISTREFRESHDELAY=5m \
    ND_MAXSIDEBARPLAYLISTS=50 \
    ND_ENABLEDOWNLOADS=true \
    ND_ENABLETRANSCODINGCONFIG=true \
    ND_AUTOTRANSCODEDOWNLOAD=false \
    ND_DEFAULTDOWNSAMPLINGFORMAT=opus \
    ND_TRANSCODING_ENABLECANCELLATION=true \
    ND_TRANSCODING_MAXCONCURRENT=1 \
    ND_TRANSCODING_MAXCONCURRENTPERUSER=1 \
    ND_TRANSCODINGCACHESIZE=2048MiB \
    ND_IMAGECACHESIZE=256MiB \
    ND_COVERARTQUALITY=75 \
    ND_UICOVERARTSIZE=300 \
    ND_UISEARCHDEBOUNCEMS=350 \
    ND_ENABLEWEBPENCODING=false \
    ND_COVERARTPRIORITY="cover.*,folder.*,front.*,embedded,external" \
    ND_ARTISTARTPRIORITY="artist.*,album/artist.*,external" \
    ND_DISCARTPRIORITY="disc*.*,cd*.*,cover.*,folder.*,front.*,discsubtitle,embedded" \
    ND_LYRICSPRIORITY=".lrc,.txt,embedded" \
    ND_ENABLEMEDIAFILECOVERART=false \
    ND_ENABLEARTWORKPRECACHE=false \
    ND_ENABLEARTWORKUPLOAD=true \
    ND_ENABLECOVERANIMATION=false \
    ND_ENABLEREPLAYGAIN=true \
    ND_ENABLENOWPLAYING=false \
    ND_ENABLEFAVOURITES=true \
    ND_ENABLESTARRATING=true \
    ND_AUTOIMPORTPLAYLISTS=false \
    ND_PLAYLISTSPATH="" \
    ND_ENABLEEXTERNALSERVICES=false \
    ND_ENABLEINSIGHTSCOLLECTOR=false \
    ND_AGENTS="" \
    ND_DEEZER_ENABLED=false \
    ND_DEEZER_LANGUAGE="ko,en" \
    ND_LASTFM_ENABLED=false \
    ND_LASTFM_LANGUAGE="ko,en" \
    ND_LASTFM_SCROBBLEFIRSTARTISTONLY=false \
    ND_LISTENBRAINZ_ENABLED=false \
    ND_LISTENBRAINZ_BASEURL=https://api.listenbrainz.org/1/ \
    ND_ENABLESCROBBLEHISTORY=false \
    ND_PROMETHEUS_ENABLED=false \
    ND_INSPECT_ENABLED=false \
    ND_PLUGINS_ENABLED=false \
    ND_PLUGINS_CACHESIZE=64MB \
    ND_PLUGINS_AUTORELOAD=false \
    ND_JUKEBOX_ENABLED=false \
    ND_ENABLEGRAVATAR=false \
    ND_ENABLELOGREDACTING=true \
    ND_ENABLESHARING=false \
    ND_DEFAULTLANGUAGE=ko \
    ND_DEFAULTTHEME=Dark \
    ND_LOGLEVEL=warn \
    ND_MAXIMAGEUPLOADSIZE=10MB \
    JBS_SQLITE_MAINT=false \
    JBS_CACHE_WARM=false \
    JBS_CACHE_WARM_LIMIT_MB=auto \
    JBS_FFMPEG_PREFLIGHT=true \
    JBS_USE_JEMALLOC=true

EXPOSE 4533

STOPSIGNAL SIGTERM

HEALTHCHECK --interval=60s --timeout=5s --start-period=75s --retries=3 \
    CMD ["/usr/local/bin/healthcheck"]

WORKDIR /app

ENTRYPOINT ["/entrypoint"]
