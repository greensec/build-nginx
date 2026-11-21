#!/usr/bin/env bash
# Build nginx packages for Debian <DIST> using upstream nginx/pkg-oss
# packaging - produces the nginx.org-style "nginx" binary package
# (nginx_<VER>-1~<codename>), a drop-in replacement for hosts that ran
# the official nginx.org builds before they dropped the suite.
#
# Required env:
#   DIST        target suite: stretch | buster | bullseye
# Optional env:
#   NGINX_TAG   pkg-oss git tag (default: 1.30.7-1 - NGINX2Root fixes)
#   PKG_OSS     pkg-oss clone URL
#   OUTDIR      .deb output dir (default: ./out)

set -euo pipefail

: "${DIST:?missing DIST}"
: "${NGINX_TAG:=1.30.7-1}"
: "${PKG_OSS:=https://github.com/nginx/pkg-oss.git}"
: "${OUTDIR:=$PWD/out}"

export DEBIAN_FRONTEND=noninteractive

# --- apt sources --------------------------------------------------------------
# EOL dists live on archive.debian.org; emptied -updates/-backports suites
# must go (a 404 breaks apt-get update). Stretch additionally needs
# stretch-backports for debhelper >= 11 (pkg-oss hardcodes compat 11;
# stretch only ships debhelper 10.2.5).
case "$DIST" in
    stretch)
        sed -i -e '/stretch-updates/d' \
            -e 's|deb\.debian\.org/debian-security|archive.debian.org/debian-security|g' \
            -e 's|deb\.debian\.org/debian|archive.debian.org/debian|g' \
            -e 's|security\.debian\.org/debian-security|archive.debian.org/debian-security|g' \
            /etc/apt/sources.list
        sed -i '/stretch-backports/d' /etc/apt/sources.list
        echo "deb http://archive.debian.org/debian stretch-backports main" \
            >>/etc/apt/sources.list
        ;;
    buster|bullseye)
        sed -i -e "/${DIST}-updates/d" -e "/${DIST}-backports/d" \
            -e 's|deb\.debian\.org/debian-security|archive.debian.org/debian-security|g' \
            -e 's|deb\.debian\.org/debian|archive.debian.org/debian|g' \
            -e 's|security\.debian\.org/debian-security|archive.debian.org/debian-security|g' \
            /etc/apt/sources.list
        ;;
esac

apt-get update -qq
apt-get install -y --no-install-recommends \
    build-essential devscripts quilt dpkg-dev debhelper lsb-release \
    libssl-dev libpcre2-dev zlib1g-dev \
    git ca-certificates curl make xsltproc lintian libxml2-utils fakeroot

if [ "$DIST" = stretch ]; then
    apt-get install -y -t stretch-backports debhelper || true
fi

# --- pkg-oss -------------------------------------------------------------------
WORK=$(mktemp -d /tmp/nginxbuild.XXXXXX)
trap 'rm -rf "$WORK"' EXIT

git clone -q --depth 1 -b "$NGINX_TAG" "$PKG_OSS" "$WORK/pkg-oss"
cd "$WORK/pkg-oss/debian"

# pkg-oss hardcodes debian/compat 11 - fall back to the distro debhelper
# level when the backports install did not provide >= 11
compat=$(dpkg-query -W -f='${Version}' debhelper | cut -d. -f1)
if [ "${compat:-0}" -lt 11 ]; then
    sed -i 's|echo "11" >|echo "10" >|g' Makefile
fi

# HTTP/3 needs a QUIC-capable OpenSSL (3.x) - EOL dists ship 1.0.x/1.1.x,
# and nginx.org's builds for them never had QUIC either
sslmaj=$(dpkg-query -W -f='${Version}' libssl-dev | cut -d. -f1)
if [ "${sslmaj:-0}" -lt 3 ]; then
    sed -i '/--with-http_v3_module/d' Makefile
fi

make base

# base target copies built files up two levels ($WORK)
mkdir -p "$OUTDIR"
cp "$WORK"/*.deb "$OUTDIR"/

echo "=== built packages ==="
ls -la "$OUTDIR"/*.deb
