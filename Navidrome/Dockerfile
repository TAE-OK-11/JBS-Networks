# syntax=docker/dockerfile:1

# [버전 설정] 최신 안정 버전으로 업데이트 완료
ARG NAVIDROME_REF=v0.60.3
ARG TAGLIB_VERSION=2.2.1
ARG JEMALLOC_VERSION=5.3.0
ARG NAVIDROME_BUILD_CORES=2
ARG GOMEMLIMIT=4.5GiB
ARG SCANSCHEDULE=0

# [최적화 설정] Zen 3 및 LTO(Link Time Optimization) 플래그 추가
ARG CPU_OPTIMIZATION_FLAGS="-O3 -march=znver3 -DNDEBUG"
ARG LTO_FLAGS="-flto"
ARG GOAMD64_VERSION=v3

#####################################################
### Stage 0: Fetch Navidrome Source
FROM alpine:3.21 AS source
ARG NAVIDROME_REF
RUN apk add --no-cache git
WORKDIR /src
RUN git clone --branch "${NAVIDROME_REF}" --depth=1 \
        https://github.com/navidrome/navidrome.git . && \
    git rev-parse --short HEAD > /src/.git_sha

#####################################################
### Stage 1: Build jemalloc (Zen 3 + LTO 최적화)
FROM debian:trixie-slim AS jemalloc-builder
ARG JEMALLOC_VERSION
ARG NAVIDROME_BUILD_CORES
ARG CPU_OPTIMIZATION_FLAGS
ARG LTO_FLAGS
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential autoconf automake libtool bzip2 wget ca-certificates && \
    rm -rf /var/lib/apt/lists/*
WORKDIR /build
RUN wget -qO jemalloc.tar.bz2 \
        "https://github.com/jemalloc/jemalloc/releases/download/${JEMALLOC_VERSION}/jemalloc-${JEMALLOC_VERSION}.tar.bz2" && \
    tar -xjf jemalloc.tar.bz2
WORKDIR /build/jemalloc-${JEMALLOC_VERSION}
RUN CFLAGS="${CPU_OPTIMIZATION_FLAGS} ${LTO_FLAGS}" CXXFLAGS="${CPU_OPTIMIZATION_FLAGS} ${LTO_FLAGS}" \
    ./configure --prefix=/usr/local --disable-cxx && \
    make -j${NAVIDROME_BUILD_CORES:-2} install && \
    strip --strip-unneeded /usr/local/lib/libjemalloc.so*

#####################################################
### Stage 2: Build UI
FROM node:23-alpine AS jsbuilder
WORKDIR /src/ui
COPY --from=source /src/ui ./
RUN --mount=type=cache,target=/root/.npm \
    npm ci --prefer-offline --no-audit --fund=false && npm run build

#####################################################
### Stage 3: Build TagLib + Navidrome (Go 1.26 + Zen 3)
FROM golang:1.26-trixie AS gobuilder
ARG TAGLIB_VERSION
ARG NAVIDROME_REF
ARG NAVIDROME_BUILD_CORES
ARG CPU_OPTIMIZATION_FLAGS
ARG LTO_FLAGS
ARG GOAMD64_VERSION

RUN apt-get update && apt-get install -y --no-install-recommends \
        gcc g++ make cmake zlib1g-dev ca-certificates pkg-config wget libutfcpp-dev && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /taglib-build
RUN wget -qO taglib.tar.gz \
        "https://github.com/taglib/taglib/releases/download/v${TAGLIB_VERSION}/taglib-${TAGLIB_VERSION}.tar.gz" && \
    tar -xzf taglib.tar.gz && cd "taglib-${TAGLIB_VERSION}" && \
    cmake -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=ON \
          -DCMAKE_C_FLAGS="${CPU_OPTIMIZATION_FLAGS} ${LTO_FLAGS}" \
          -DCMAKE_CXX_FLAGS="${CPU_OPTIMIZATION_FLAGS} ${LTO_FLAGS}" \
          -DCMAKE_INSTALL_PREFIX=/usr/local \
          -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=ON . && \
    make -j${NAVIDROME_BUILD_CORES:-2} install && ldconfig

WORKDIR /src
COPY --from=source /src/go.mod /src/go.sum ./
RUN --mount=type=cache,target=/go/pkg/mod go mod download

COPY --from=source /src ./
COPY --from=jsbuilder /src/ui/build ./ui/build/

# CGO_CFLAGS_ALLOW 복구 (LTO 플래그 통과를 위해 필수)
ENV GOAMD64=${GOAMD64_VERSION} \
    CGO_ENABLED=1 \
    GOPROXY=https://proxy.golang.org,direct \
    GOMODCACHE=/go/pkg/mod \
    GOCACHE=/root/.cache/go-build \
    PKG_CONFIG_PATH=/usr/local/lib/pkgconfig \
    CGO_CFLAGS="${CPU_OPTIMIZATION_FLAGS} ${LTO_FLAGS} -I/usr/local/include/taglib" \
    CGO_CXXFLAGS="${CPU_OPTIMIZATION_FLAGS} ${LTO_FLAGS} -I/usr/local/include/taglib" \
    CGO_CFLAGS_ALLOW="--define-prefix|-flto" \
    CGO_LDFLAGS="-L/usr/local/lib -Wl,--gc-sections -Wl,--as-needed"

RUN mkdir -p /out

RUN --mount=type=cache,target=/root/.cache/go-build \
    --mount=type=cache,target=/go/pkg/mod \
    GIT_SHA="$(cat /src/.git_sha 2>/dev/null || echo dev)" && \
    GOOS=linux GOARCH=amd64 go build -p ${NAVIDROME_BUILD_CORES:-2} \
        -trimpath -buildvcs=false \
        -tags=" netgo sqlite_fts5 sqlite_foreign_keys embed" \
        -ldflags="-s -w -buildid= -X github.com/navidrome/navidrome/consts.gitSha=${GIT_SHA} -X github.com/navidrome/navidrome/consts.gitTag=${NAVIDROME_REF}" \
        -o /out/navidrome

#####################################################
### Stage 4: Runtime
FROM debian:trixie-slim AS release
LABEL maintainer="JBS Networks"

# 타임존(tzdata) 패키지 복구
RUN apt-get update && apt-get install -y --no-install-recommends \
        ffmpeg libavcodec-extra curl sqlite3 ca-certificates zlib1g libstdc++6 tzdata && \
    rm -rf /var/lib/apt/lists/*

# FFmpeg 코어 강제 제한 래퍼 복구
RUN mv /usr/bin/ffmpeg /usr/bin/ffmpeg.real && \
    cat > /usr/bin/ffmpeg <<'EOF'
#!/bin/sh
exec /usr/bin/ffmpeg.real -threads 2 "$@"
EOF
RUN chmod +x /usr/bin/ffmpeg

COPY --from=jemalloc-builder /usr/local/lib/libjemalloc.so.2 /usr/local/lib/
COPY --from=gobuilder /usr/local/lib/libtag.so* /usr/local/lib/
RUN echo "/usr/local/lib" > /etc/ld.so.conf.d/local.conf && ldconfig

RUN groupadd -g 1000 navidrome && \
    useradd -u 1000 -g 1000 -r -M -d /nonexistent -s /usr/sbin/nologin navidrome && \
    mkdir -p /app /data /music /data/cache && \
    chown -R 1000:1000 /app /data /music

COPY --chown=1000:1000 --chmod=755 --from=gobuilder /out/navidrome /app/navidrome
RUN touch /.nddockerenv && chown 1000:1000 /.nddockerenv

RUN cat > /entrypoint.sh <<'EOF'
#!/bin/sh
set -e
# ND_DBPATH에서 순수 파일 경로만 유연하게 추출
DB_FILE=$(echo "${ND_DBPATH}" | cut -d'?' -f1)
if [ -n "${DB_FILE}" ] && [ -f "${DB_FILE}" ] && command -v sqlite3 >/dev/null 2>&1; then
  sqlite3 "${DB_FILE}" "PRAGMA wal_autocheckpoint=4000; PRAGMA wal_checkpoint(PASSIVE);" || true
fi
exec /app/navidrome "$@"
EOF
RUN chmod +x /entrypoint.sh && chown 1000:1000 /entrypoint.sh

USER 1000:1000
VOLUME ["/data", "/music"]

ARG NAVIDROME_BUILD_CORES
ARG GOMEMLIMIT
ARG SCANSCHEDULE

# TZ 복구 및 narenas:1, _timeout 복구
ENV TZ=Asia/Seoul \
    LD_PRELOAD=/usr/local/lib/libjemalloc.so.2 \
    MALLOC_CONF="narenas:1,tcache:false" \
    GOMEMLIMIT=$GOMEMLIMIT \
    GOMAXPROCS=${NAVIDROME_BUILD_CORES:-2} \
    ND_SCANSCHEDULE=$SCANSCHEDULE \
    ND_MUSICFOLDER=/music \
    ND_DATAFOLDER=/data \
    ND_CONFIGFILE=/data/navidrome.toml \
    ND_CACHEFOLDER=/data/cache \
    ND_DBPATH="/data/navidrome.db?cache=shared&_journal_mode=WAL&_synchronous=NORMAL&_timeout=30000&_foreign_keys=on" \
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
    CMD curl -fSs "http://127.0.0.1:${ND_PORT}/ping" || exit 1

WORKDIR /app
ENTRYPOINT ["/entrypoint.sh"]
