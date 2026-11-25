#!/usr/bin/env bash
# Build nginx packages for Debian <DIST> using upstream nginx/pkg-oss
# packaging - produces the nginx.org-style "nginx" binary package
# (nginx_<VER>-1~<codename>), a drop-in replacement for hosts that ran
# the official nginx.org builds before they dropped the suite.
#
# Required env:
#   DIST        target suite: jessie | stretch | buster | bullseye
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
    jessie)
        cat >/etc/apt/sources.list <<EOF
deb http://archive.debian.org/debian jessie main
deb http://archive.debian.org/debian-security jessie/updates main
EOF
        ;;
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
# bootstrap for the ELTS key fetch below (https); stretch's apt 1.4 still
# needs the external https transport
apt-get install -y --no-install-recommends ca-certificates curl
if [ "$DIST" = stretch ]; then
    apt-get install -y --no-install-recommends apt-transport-https
fi

# Freexian Extended LTS carries the only remaining security updates for these
# EOL dists - build against its patched library variants (openssl, zlib,
# pcre) so the runtime deps match what ELTS-configured hosts have. The
# ${DIST}-lts suites are partial; the archive lines above still provide the
# base. jessie is excluded - add-repository.sh gives its hosts no ELTS repo,
# so ELTS-versioned deps would be unsatisfiable there.
case "$DIST" in
    stretch|buster|bullseye)
        install -m0755 -d /etc/apt/keyrings
        curl -fsSL https://deb.freexian.com/extended-lts/archive-key.gpg \
            -o /etc/apt/keyrings/freexian-elts.gpg
        cat >/etc/apt/sources.list.d/freexian-elts.list <<EOF
deb [signed-by=/etc/apt/keyrings/freexian-elts.gpg] https://deb.freexian.com/extended-lts ${DIST}-lts main contrib non-free
EOF
        ;;
esac
apt-get update -qq

# jessie has no libpcre2-dev - nginx configure falls back to PCRE1
pcredev=libpcre2-dev
[ "$DIST" = jessie ] && pcredev=libpcre3-dev
apt-get install -y --no-install-recommends \
    build-essential devscripts quilt dpkg-dev debhelper lsb-release \
    libssl-dev "$pcredev" zlib1g-dev \
    git ca-certificates curl make xsltproc lintian libxml2-utils fakeroot

if [ "$DIST" = stretch ]; then
    apt-get install -y -t stretch-backports debhelper || true
fi

# --- pkg-oss -------------------------------------------------------------------
WORK=$(mktemp -d /tmp/nginxbuild.XXXXXX)
trap 'rm -rf "$WORK"' EXIT

git clone -q --depth 1 -b "$NGINX_TAG" "$PKG_OSS" "$WORK/pkg-oss"
cd "$WORK/pkg-oss/debian"

# pkg-oss hardcodes debian/compat 11 and Build-Depends debhelper (>= 11) -
# fall back to the distro debhelper level when no >= 11 is available
# (buster ships 12, stretch gets 11 via backports, jessie only has 9)
compat=$(dpkg-query -W -f='${Version}' debhelper | cut -d. -f1)
if [ "${compat:-0}" -lt 11 ]; then
    sed -i "s|echo \"11\" >|echo \"${compat}\" >|g" Makefile
    # the static template file is copied over the echoed one during base
    sed -i "s|^[0-9]*$|${compat}|" debian/compat
    sed -i "s|debhelper (>= 11)|debhelper (>= ${compat})|g" debian/nginx.control.in
fi
# --no-stop-on-upgrade needs debhelper >= 10; on older ones accept the
# default (service restarts during upgrade)
if [ "${compat:-0}" -lt 10 ]; then
    sed -i 's| --no-stop-on-upgrade||g' debian/nginx.rules.in
    # dh_installsystemd does not exist before debhelper 10; the sysvinit
    # script still gets generated into a systemd unit on jessie
    sed -i '/dh_installsystemd/d' debian/nginx.rules.in
fi
# jessie has no libpcre2 - declare the PCRE1 package instead
if [ "$DIST" = jessie ]; then
    sed -i 's|libpcre2-dev|libpcre3-dev|g' debian/nginx.control.in
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
