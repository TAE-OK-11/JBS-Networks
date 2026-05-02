# JBS Jellyfin Docker Image (Zen3 + jemalloc + custom FFmpeg)

이 디렉터리는 `TAE-OK-11/JBS-Networks` 스타일에 맞춘 Jellyfin 전용 Docker 빌드 구성을 제공합니다.

## 핵심 포인트

- `debian:trixie-slim` digest 고정
- multi-stage 빌드
- `jemalloc 5.3.1` 소스 빌드 + `LD_PRELOAD`
- `FFmpeg` 커스텀 빌드(영상 트랜스코딩 호환 중심)
- `clang/lld/llvm` + Zen3 + ThinLTO 적용
- non-root (`UID/GID=1000`)
- 볼륨: `/config`, `/cache`, `/media`
- 포트: `8096`
- HTTP 기반 `HEALTHCHECK`
- 기본 시간대: `Asia/Seoul`

## 빌드

레포 루트에서:

```bash
docker build -t tae00217/jbs-jellyfin:ultra -f jellyfin/Dockerfile jellyfin
```

## 실행 예시 (docker run)

```bash
docker run -d \
  --name jellyfin \
  -p 8096:8096 \
  -e TZ=Asia/Seoul \
  -v jellyfin-config:/config \
  -v jellyfin-cache:/cache \
  -v /path/to/media:/media \
  tae00217/jbs-jellyfin:ultra
```

## 실행 예시 (docker compose)

```yaml
services:
  jellyfin:
    image: tae00217/jbs-jellyfin:ultra
    container_name: jellyfin
    ports:
      - "8096:8096"
    environment:
      TZ: Asia/Seoul
    volumes:
      - jellyfin-config:/config
      - jellyfin-cache:/cache
      - /path/to/media:/media
    restart: unless-stopped

volumes:
  jellyfin-config:
  jellyfin-cache:
```

## FFmpeg/FFprobe 확인

```bash
docker exec jellyfin ffmpeg -version
docker exec jellyfin ffprobe -version
```

동적 링크 확인:

```bash
docker exec jellyfin sh -lc 'ldd $(which ffmpeg)'
```

## jemalloc 적용 확인

환경변수 확인:

```bash
docker exec jellyfin sh -lc 'echo "$LD_PRELOAD"'
```

프로세스 메모리 맵 확인:

```bash
docker exec jellyfin sh -lc 'grep jemalloc /proc/1/maps'
```

## 참고

- Jellyfin 서버(.NET)는 공식 portable 아카이브를 사용해 안정성과 유지보수성을 우선했습니다.
- Native 성능 최적화는 jemalloc/FFmpeg 중심으로 적용했습니다.
