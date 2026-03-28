#####################################################
### Stage 4: Runtime
FROM debian:trixie-slim AS release
LABEL maintainer="JBS Networks"

RUN apt-get update && apt-get install -y --no-install-recommends \
        ffmpeg libavcodec-extra curl sqlite3 ca-certificates zlib1g libstdc++6 tzdata && \
    rm -rf /var/lib/apt/lists/*

# FFmpeg 래퍼: 기본값을 환경 변수와 연동하여 자원 격리 보장
RUN mv /usr/bin/ffmpeg /usr/bin/ffmpeg.real && \
    cat > /usr/bin/ffmpeg <<'EOF'
#!/bin/sh
exec /usr/bin/ffmpeg.real -threads "${FFMPEG_THREADS:-2}" "$@"
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

# [수정됨] jemalloc 신규 최적화 옵션 및 환경 변수 적용
ENV TZ=Asia/Seoul \
    LD_PRELOAD=/usr/local/lib/libjemalloc.so.2 \
    MALLOC_CONF="background_thread:true,metadata_thp:auto,percpu_arena:percpu,tcache_max:32768,dirty_decay_ms:10000,muzzy_decay_ms:20000,stats_print:false" \
    GOMEMLIMIT=$GOMEMLIMIT \
    GOMAXPROCS=${NAVIDROME_BUILD_CORES} \
    FFMPEG_THREADS=${NAVIDROME_BUILD_CORES} \
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
