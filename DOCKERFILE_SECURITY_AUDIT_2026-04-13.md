# Dockerfile 보안/오류 점검 리포트 (2026-04-13)

대상:
- `litellm/Dockerfile`
- `navidrome/Dockerfile`

## 요약

- `litellm/Dockerfile`: **치명적 문법 오류는 없지만**, 런타임 루트 실행/이미지 고정 미흡/패키지 버전 고정 미흡/과도한 복사 범위 등 보안 하드닝 여지가 큼.
- `navidrome/Dockerfile`: 전반적으로 멀티스테이지·digest pinning·비루트 실행·체크섬 검증 등 **보안 성숙도가 높은 편**. 다만 소스 취득 방식(`git clone --branch tag`)의 공급망 고정성은 더 강화 가능.

---

## 1) litellm/Dockerfile 점검

### 확인된 이슈

1. **런타임 이미지/빌더 이미지 digest 미고정**
   - `FROM debian:trixie AS builder`
   - `FROM debian:trixie AS runtime`
   - 태그만 사용하면 동일 Dockerfile이라도 시점별로 다른 베이스 레이어를 받을 수 있음.

2. **런타임에서 root 사용자로 실행**
   - `USER` 지정이 없어 기본 root로 컨테이너 시작.
   - 서비스 침해 시 컨테이너 내부 권한이 과도하게 큼.

3. **공급망 버전 고정 미흡 (npm global install)**
   - `npm install -g prisma` (버전 미지정)
   - 최신 버전 변동 시 재현성 및 안정성 저하 가능.

4. **런타임 아티팩트 최소화 부족**
   - `COPY --from=builder /app /app`
   - 빌드 산출물 외 개발 관련 파일이 함께 포함될 가능성.

5. **패키지 설치 버전 고정 미흡**
   - `apt-get install`에 버전 핀 없음.
   - 재현성과 CVE 대응 통제력이 낮아짐.

### 개선 권장

- `FROM debian:trixie@sha256:...` 형태로 digest pinning.
- 전용 비루트 사용자 생성 후 `USER` 적용.
- `prisma` 버전 명시(예: `prisma@x.y.z`) 및 lock 관리.
- 런타임에는 wheel/site-packages + 실행 스크립트만 복사.
- 최소 권한 원칙: 불필요 패키지(특히 런타임 `nodejs`) 필요성 재검토.

---

## 2) navidrome/Dockerfile 점검

### 강점

1. **베이스 이미지 digest pinning 적용**
   - Debian/Node/Go/Rust 모두 digest 고정.

2. **다운로드 아카이브 체크섬 검증**
   - jemalloc / ffmpeg / taglib SHA256 검증 포함.

3. **비루트 실행**
   - UID/GID 1000 사용자 생성 후 `USER 1000:1000`.

4. **헬스체크 및 엔트리포인트 분리**
   - `HEALTHCHECK` 존재, rust 기반 보조 바이너리 분리.

5. **FFMPEG_THREADS 입력 검증**
   - shell wrapper에서 정수 강제 변환 처리.

### 보완 필요 포인트

1. **소스 고정성 강화 필요**
   - `git clone --branch "${NAVIDROME_REF}" --depth=1 ...`
   - 태그 기준 fetch는 편리하지만, 엄밀한 공급망 재현성 측면에선 commit SHA 고정이 더 안전.

2. **apt 설치 버전 고정 부재**
   - digest pinning이 있어도 apt repo 최신 패키지에 영향 받을 수 있음.

### 개선 권장

- `NAVIDROME_REF`를 태그 대신 커밋 SHA로 고정하고, clone 후 SHA 검증 절차 추가.
- 고정이 필요한 핵심 패키지는 버전 pinning 또는 내부 미러 전략 적용.

---

## 결론

- **즉시 위험도가 더 높은 쪽은 `litellm/Dockerfile`** (root 실행, mutable base, 공급망 버전 고정 부족).
- **`navidrome/Dockerfile`은 상대적으로 우수**하며, 공급망 고정(태그→커밋 SHA)만 보완하면 운영 신뢰도가 더욱 높아짐.


---

## 3) 2026-04-15 버전 상향 반영 내용 및 성능 영향

요청된 버전 상향 반영:
- `nginx/Dockerfile`
  - `AWSLC_VERSION`: `v1.71.0` → `v1.72.0`
  - `JEMALLOC_VERSION`: `5.3.0` → `5.3.1`
  - `JEMALLOC_SHA256`: `5.3.1` 아카이브 기준으로 갱신
- `navidrome/Dockerfile`
  - `NAVIDROME_REF`: `v0.61.1` → `v0.61.2`
  - `JEMALLOC_VERSION`: `5.3.0` → `5.3.1`
  - `JEMALLOC_SHA256`: `5.3.1` 아카이브 기준으로 갱신

### 기대 효과 (PR 본문에 기재 가능한 내용)

1. **메모리 할당 안정성/효율 개선(jemalloc 5.3.1)**
   - `nginx`, `navidrome` 모두 jemalloc을 공통 사용하므로, 할당기 마이너 릴리스 반영으로 장시간 구동 시 메모리 단편화 및 allocator 관련 병목 가능성을 완화할 수 있음.
   - 특히 다수 연결/스트리밍처럼 alloc/free 빈도가 높은 워크로드에서 tail latency 개선 가능성이 있음.

2. **TLS/암호화 스택 최신화(AWS-LC v1.72.0)**
   - `nginx`의 TLS 경로에서 최신 AWS-LC 코드를 사용해 보안 수정/최적화 반영 가능.
   - 실제 처리량 증가는 트래픽 패턴과 CPU의 crypto extension 활용도에 좌우되나, 최신 릴리스 반영으로 성능 및 안정성 회귀 리스크를 낮춤.

3. **애플리케이션 릴리스 반영(Navidrome v0.61.2)**
   - Navidrome의 최신 패치 릴리스를 빌드 대상으로 사용하여, 상위 프로젝트의 버그 수정 및 동작 안정성 향상을 기대할 수 있음.

### 검증 메모

- jemalloc `5.3.1` tarball SHA256:
  - `3826bc80232f22ed5c4662f3034f799ca316e819103bdc7bb99018a421706f92`
- 두 Dockerfile의 버전/체크섬 인자 반영 상태를 정규식 검색으로 재확인.
