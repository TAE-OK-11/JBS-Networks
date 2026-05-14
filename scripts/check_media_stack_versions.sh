#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NAV_DOCKERFILE="$ROOT_DIR/navidrome/Dockerfile"
NGX_DOCKERFILE="$ROOT_DIR/nginx/Dockerfile"
need(){ command -v "$1" >/dev/null 2>&1 || { echo "missing dependency: $1" >&2; exit 1; }; }
need curl; need jq; need sed; need rg; need sort
extract_arg(){ sed -n "s/^ARG $2=\"\{0,1\}\([^\" ]*\)\"\{0,1\}$/\1/p" "$1" | head -n1; }

check_github_latest(){
  local label="$1" repo="$2" current="$3" latest
  latest="$(curl -fsSL "https://api.github.com/repos/${repo}/releases/latest" | jq -r '.tag_name // empty')"
  [[ -z "$latest" ]] && { echo "[WARN] $label: latest release API unavailable"; return; }
  local current_norm="${current#v}" latest_norm="${latest#v}"
  [[ "$latest_norm" == "$current_norm" ]] && printf "[OK] %-18s current=%s latest=%s\n" "$label" "$current" "$latest" || printf "[UPDATE] %-14s current=%s latest=%s\n" "$label" "$current" "$latest"
}

check_ffmpeg_latest(){ local current="$1" latest; latest="$(curl -fsSL https://ffmpeg.org/releases/ | rg -o 'ffmpeg-[0-9]+\.[0-9]+(\.[0-9]+)?\.tar\.bz2' | sed 's/^ffmpeg-//;s/\.tar\.bz2$//' | sort -V | tail -n1)"; [[ -z "$latest" ]] && { echo "[WARN] ffmpeg: parse failed"; return; }; [[ "$latest" == "$current" ]] && printf "[OK] %-18s current=%s latest=%s\n" "ffmpeg" "$current" "$latest" || printf "[UPDATE] %-14s current=%s latest=%s\n" "ffmpeg" "$current" "$latest"; }
check_opus_latest(){ local current="$1" latest; latest="$(curl -fsSL https://downloads.xiph.org/releases/opus/ | rg -o 'opus-[0-9]+\.[0-9]+(\.[0-9]+)?\.tar\.gz' | sed 's/^opus-//;s/\.tar\.gz$//' | sort -V | tail -n1)"; [[ -z "$latest" ]] && { echo "[WARN] opus: parse failed"; return; }; [[ "$latest" == "$current" ]] && printf "[OK] %-18s current=%s latest=%s\n" "opus" "$current" "$latest" || printf "[UPDATE] %-14s current=%s latest=%s\n" "opus" "$current" "$latest"; }
check_dockerhub_latest(){
  local label="$1" repo="$2" current="$3" major latest
  major="${current%%.*}"
  latest="$(curl -fsSL "https://registry.hub.docker.com/v2/repositories/${repo}/tags?page_size=200" | jq -r '.results[].name' | rg "^${major}\.[0-9]+\.[0-9]+$" | sort -V | tail -n1)"
  [[ -z "$latest" ]] && { echo "[WARN] $label: docker hub tag parse failed"; return; }
  [[ "$latest" == "$current" ]] && printf "[OK] %-18s current=%s latest=%s\n" "$label" "$current" "$latest" || printf "[UPDATE] %-14s current=%s latest=%s\n" "$label" "$current" "$latest"
}

check_nginx_latest(){ local current="$1" stable; stable="$(curl -fsSL https://nginx.org/en/download.html | tr '\n' ' ' | sed -n 's/.*Stable version<\/h4><\/center><table width="100%"><tr><td width="20%"><a href="\/en\/CHANGES-[0-9.]*">CHANGES-[0-9.]*<\/a><\/td><td width="20%"><a href="\/download\/nginx-\([0-9.]*\)\.tar\.gz">.*/\1/p')"; [[ -z "$stable" ]] && { echo "[WARN] nginx stable version parsing failed"; return; }; [[ "$stable" == "$current" ]] && printf "[OK] %-18s current=%s latest=%s\n" "nginx(stable)" "$current" "$stable" || printf "[UPDATE] %-14s current=%s latest=%s\n" "nginx(stable)" "$current" "$stable"; }

extract_version_from_image(){ echo "$1" | sed -E 's/^[^:]+:([^-]+).*/\1/'; }

navidrome_ref="$(extract_arg "$NAV_DOCKERFILE" NAVIDROME_REF)"
ffmpeg_ver="$(extract_arg "$NAV_DOCKERFILE" FFMPEG_VERSION)"
opus_ver="$(extract_arg "$NAV_DOCKERFILE" OPUS_VERSION)"
taglib_ver="$(extract_arg "$NAV_DOCKERFILE" TAGLIB_VERSION)"
jemalloc_ver="$(extract_arg "$NAV_DOCKERFILE" JEMALLOC_VERSION)"
node_img="$(extract_arg "$NAV_DOCKERFILE" NODE_IMAGE)"
go_img="$(extract_arg "$NAV_DOCKERFILE" GOLANG_IMAGE)"
rust_img="$(extract_arg "$NAV_DOCKERFILE" RUST_IMAGE)"

nginx_ver="$(extract_arg "$NGX_DOCKERFILE" NGINX_VERSION)"
cargoc_ver="$(extract_arg "$NGX_DOCKERFILE" CARGOC_VERSION)"
awslc_ver="$(extract_arg "$NGX_DOCKERFILE" AWSLC_VERSION)"
pcre2_ver="$(extract_arg "$NGX_DOCKERFILE" PCRE2_VERSION)"
zstd_ver="$(extract_arg "$NGX_DOCKERFILE" ZSTD_VERSION)"

node_ver="$(extract_version_from_image "$node_img")"
go_ver="$(extract_version_from_image "$go_img")"
rust_ver="$(extract_version_from_image "$rust_img")"

echo "== Navidrome stack =="
check_github_latest "navidrome" "navidrome/navidrome" "$navidrome_ref"
check_ffmpeg_latest "$ffmpeg_ver"
check_opus_latest "$opus_ver"
check_github_latest "taglib" "taglib/taglib" "$taglib_ver"
check_github_latest "jemalloc" "jemalloc/jemalloc" "$jemalloc_ver"
check_dockerhub_latest "node" "library/node" "$node_ver"
check_dockerhub_latest "golang" "library/golang" "$go_ver"
check_dockerhub_latest "rust" "library/rust" "$rust_ver"

echo
echo "== NGINX stack =="
check_nginx_latest "$nginx_ver"
check_github_latest "aws-lc" "aws/aws-lc" "$awslc_ver"
check_github_latest "cargo-c" "lu-zero/cargo-c" "$cargoc_ver"
check_github_latest "zstd" "facebook/zstd" "v$zstd_ver"
check_github_latest "pcre2" "PCRE2Project/pcre2" "pcre2-$pcre2_ver"

echo
echo "Checked at (UTC): $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "Done."
