#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NAV_DOCKERFILE="$ROOT_DIR/navidrome/Dockerfile"
NGX_DOCKERFILE="$ROOT_DIR/nginx/Dockerfile"
need(){ command -v "$1" >/dev/null 2>&1 || { echo "missing dependency: $1" >&2; exit 1; }; }
need awk; need curl; need git; need jq; need sed; need rg; need sort
extract_arg(){ sed -n "s/^ARG $2=\"\{0,1\}\([^\" ]*\)\"\{0,1\}$/\1/p" "$1" | head -n1; }

check_github_latest(){
  local label="$1" repo="$2" current="$3" latest
  latest="$(curl -fsSL "https://api.github.com/repos/${repo}/releases/latest" 2>/dev/null | jq -r '.tag_name // empty')" || latest=""
  [[ -z "$latest" ]] && { echo "[WARN] $label: latest release API unavailable"; return; }
  local current_norm="${current#v}" latest_norm="${latest#v}"
  [[ "$latest_norm" == "$current_norm" ]] && printf "[OK] %-18s current=%s latest=%s\n" "$label" "$current" "$latest" || printf "[UPDATE] %-14s current=%s latest=%s\n" "$label" "$current" "$latest"
}

check_github_latest_tag(){
  local label="$1" repo="$2" current="$3" latest
  latest="$(git ls-remote --tags --refs "https://github.com/${repo}.git" 2>/dev/null | awk -F/ '{print $3}' | sort -V | tail -n1)" || latest=""
  [[ -z "$latest" ]] && { echo "[WARN] $label: tag lookup unavailable"; return; }
  [[ "${latest#v}" == "${current#v}" ]] && printf "[OK] %-18s current=%s latest=%s\n" "$label" "$current" "$latest" || printf "[UPDATE] %-14s current=%s latest=%s\n" "$label" "$current" "$latest"
}

check_github_head(){
  local label="$1" repo="$2" current="$3" latest
  latest="$(git ls-remote "https://github.com/${repo}.git" HEAD 2>/dev/null | awk '{print $1}')" || latest=""
  [[ -z "$latest" ]] && { echo "[WARN] $label: HEAD lookup unavailable"; return; }
  [[ "$latest" == "$current" ]] && printf "[OK] %-18s current=%s latest=%s\n" "$label" "${current:0:12}" "${latest:0:12}" || printf "[UPDATE] %-14s current=%s latest=%s\n" "$label" "${current:0:12}" "${latest:0:12}"
}

check_crates_latest(){
  local label="$1" crate="$2" current="$3" latest
  latest="$(curl -A 'JBS-version-check/1.0' -fsSL "https://crates.io/api/v1/crates/${crate}" 2>/dev/null | jq -r '.crate.max_stable_version // empty')" || latest=""
  [[ -z "$latest" ]] && { echo "[WARN] $label: crates.io API unavailable"; return; }
  [[ "$latest" == "$current" ]] && printf "[OK] %-18s current=%s latest=%s\n" "$label" "$current" "$latest" || printf "[UPDATE] %-14s current=%s latest=%s\n" "$label" "$current" "$latest"
}

check_ffmpeg_latest(){
  local current="$1" latest
  latest="$(curl -fsSL https://ffmpeg.org/releases/ 2>/dev/null | rg -o 'ffmpeg-[0-9]+\.[0-9]+(\.[0-9]+)?\.tar\.bz2' | sed 's/^ffmpeg-//;s/\.tar\.bz2$//' | sort -V | tail -n1)" || latest=""
  [[ -z "$latest" ]] && { echo "[WARN] ffmpeg: parse failed"; return; }
  [[ "$latest" == "$current" ]] && printf "[OK] %-18s current=%s latest=%s\n" "ffmpeg" "$current" "$latest" || printf "[UPDATE] %-14s current=%s latest=%s\n" "ffmpeg" "$current" "$latest"
}

check_opus_latest(){
  local current="$1" latest
  latest="$(curl -fsSL https://downloads.xiph.org/releases/opus/ 2>/dev/null | rg -o 'opus-[0-9]+\.[0-9]+(\.[0-9]+)?\.tar\.gz' | sed 's/^opus-//;s/\.tar\.gz$//' | sort -V | tail -n1)" || latest=""
  [[ -z "$latest" ]] && { echo "[WARN] opus: parse failed"; return; }
  [[ "$latest" == "$current" ]] && printf "[OK] %-18s current=%s latest=%s\n" "opus" "$current" "$latest" || printf "[UPDATE] %-14s current=%s latest=%s\n" "opus" "$current" "$latest"
}

check_dockerhub_latest(){
  local label="$1" repo="$2" current="$3" major latest
  major="${current%%.*}"
  latest="$(curl -fsSL "https://registry.hub.docker.com/v2/repositories/${repo}/tags?page_size=200" 2>/dev/null | jq -r '.results[].name' | rg "^${major}\.[0-9]+\.[0-9]+$" | sort -V | tail -n1)" || latest=""
  [[ -z "$latest" ]] && { echo "[WARN] $label: docker hub tag parse failed"; return; }
  [[ "$latest" == "$current" ]] && printf "[OK] %-18s current=%s latest=%s\n" "$label" "$current" "$latest" || printf "[UPDATE] %-14s current=%s latest=%s\n" "$label" "$current" "$latest"
}

check_nginx_latest(){
  local current="$1" latest
  latest="$(curl -fsSL https://nginx.org/download/ 2>/dev/null | rg -o 'nginx-[0-9]+\.[0-9]+\.[0-9]+\.tar\.gz' | sed 's/^nginx-//;s/\.tar\.gz$//' | sort -Vu | tail -n1)" || latest=""
  [[ -z "$latest" ]] && { echo "[WARN] nginx mainline version parsing failed"; return; }
  [[ "$latest" == "$current" ]] && printf "[OK] %-18s current=%s latest=%s\n" "nginx(mainline)" "$current" "$latest" || printf "[UPDATE] %-14s current=%s latest=%s\n" "nginx(mainline)" "$current" "$latest"
}

check_dockerfile_frontend(){
  local current="$1" latest
  latest="$(curl -fsSL 'https://registry.hub.docker.com/v2/repositories/docker/dockerfile/tags?page_size=100' 2>/dev/null | jq -r '.results[].name' | rg '^[0-9]+\.[0-9]+$' | sort -V | tail -n1)" || latest=""
  [[ -z "$latest" ]] && { echo "[WARN] dockerfile frontend tag lookup unavailable"; return; }
  [[ "$latest" == "$current" ]] && printf "[OK] %-18s current=%s latest=%s\n" "dockerfile" "$current" "$latest" || printf "[UPDATE] %-14s current=%s latest=%s\n" "dockerfile" "$current" "$latest"
}

extract_version_from_image(){ echo "$1" | sed -E 's/^[^:]+:([^-]+).*/\1/'; }

navidrome_ref="$(extract_arg "$NAV_DOCKERFILE" NAVIDROME_REF)"
ffmpeg_ver="$(extract_arg "$NAV_DOCKERFILE" FFMPEG_VERSION)"
opus_ver="$(extract_arg "$NAV_DOCKERFILE" OPUS_VERSION)"
taglib_ver="$(extract_arg "$NAV_DOCKERFILE" TAGLIB_VERSION)"
jemalloc_ver="$(extract_arg "$NAV_DOCKERFILE" JEMALLOC_VERSION)"
rusqlite_ver="$(extract_arg "$NAV_DOCKERFILE" RUSQLITE_VERSION)"
walkdir_ver="$(extract_arg "$NAV_DOCKERFILE" WALKDIR_VERSION)"
node_img="$(extract_arg "$NAV_DOCKERFILE" NODE_IMAGE)"
go_img="$(extract_arg "$NAV_DOCKERFILE" GOLANG_IMAGE)"
rust_img="$(extract_arg "$NAV_DOCKERFILE" RUST_IMAGE)"

nginx_ver="$(extract_arg "$NGX_DOCKERFILE" NGINX_VERSION)"
cargoc_ver="$(extract_arg "$NGX_DOCKERFILE" CARGOC_VERSION)"
awslc_ver="$(extract_arg "$NGX_DOCKERFILE" AWSLC_VERSION)"
pcre2_ver="$(extract_arg "$NGX_DOCKERFILE" PCRE2_VERSION)"
zstd_ver="$(extract_arg "$NGX_DOCKERFILE" ZSTD_VERSION)"
zlibrs_ver="$(extract_arg "$NGX_DOCKERFILE" ZLIBRS_VERSION)"
brotli_ver="$(extract_arg "$NGX_DOCKERFILE" BROTLI_VERSION)"
ngx_zstd_ver="$(extract_arg "$NGX_DOCKERFILE" NGX_ZSTD_MODULE_VERSION)"
ngx_brotli_ref="$(extract_arg "$NGX_DOCKERFILE" NGX_BROTLI_REF)"
dockerfile_frontend="$(sed -n 's|^# syntax=docker/dockerfile:\([^@ ]*\).*|\1|p' "$NAV_DOCKERFILE" | head -n1)"

node_ver="$(extract_version_from_image "$node_img")"
go_ver="$(extract_version_from_image "$go_img")"
rust_ver="$(extract_version_from_image "$rust_img")"

echo "== Navidrome stack =="
if [[ "$navidrome_ref" == "master" ]]; then
  printf "[INFO] %-16s current=%s (tracking branch)\n" "navidrome" "$navidrome_ref"
else
  check_github_latest "navidrome" "navidrome/navidrome" "$navidrome_ref"
fi
check_ffmpeg_latest "$ffmpeg_ver"
check_opus_latest "$opus_ver"
check_github_latest "taglib" "taglib/taglib" "$taglib_ver"
check_github_latest "jemalloc" "jemalloc/jemalloc" "$jemalloc_ver"
check_crates_latest "rusqlite" "rusqlite" "$rusqlite_ver"
check_crates_latest "walkdir" "walkdir" "$walkdir_ver"
check_dockerhub_latest "node" "library/node" "$node_ver"
check_dockerhub_latest "golang" "library/golang" "$go_ver"
check_dockerhub_latest "rust" "library/rust" "$rust_ver"
check_dockerfile_frontend "$dockerfile_frontend"

echo
echo "== NGINX stack =="
check_nginx_latest "$nginx_ver"
check_github_latest "aws-lc" "aws/aws-lc" "$awslc_ver"
check_github_latest "cargo-c" "lu-zero/cargo-c" "$cargoc_ver"
check_github_latest "zstd" "facebook/zstd" "v$zstd_ver"
check_github_latest "zlib-rs" "trifectatechfoundation/zlib-rs" "$zlibrs_ver"
check_github_latest "brotli" "google/brotli" "$brotli_ver"
check_github_latest_tag "ngx-zstd" "HanadaLee/ngx_http_zstd_module" "$ngx_zstd_ver"
check_github_head "ngx-brotli" "google/ngx_brotli" "$ngx_brotli_ref"
check_github_latest "pcre2" "PCRE2Project/pcre2" "pcre2-$pcre2_ver"

echo
echo "Checked at (UTC): $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "Done."
