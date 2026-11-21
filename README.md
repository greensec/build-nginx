# build-nginx

Debian packages of **nginx** for suites the official [nginx.org package
repository](https://nginx.org/packages/debian/) dropped: `stretch`,
`buster`, `bullseye` (amd64).

The packages are built with upstream's own
[pkg-oss](https://github.com/nginx/pkg-oss) packaging, so they are drop-in
replacements for the nginx.org builds: same `nginx` package name, same
version scheme (`<ver>-1~<codename>`), `Conflicts:/Replaces:` the Debian
`nginx-*` flavour packages.

## Why

nginx.org stopped publishing for EOL Debian suites - e.g. bullseye tops
out at 1.30.5 while the NGINX2Root fixes (CVE-2026-123633, -123007,
-123634, -113425, -121810) shipped only in 1.30.7/1.31.9. Hosts that run
the nginx.org builds on those suites have no upstream upgrade path.

Where a config supports it, prefer **Debian's own nginx** +
[Freexian ELTS](https://deb.freexian.com/extended-lts) instead: ELTS
backports the same fixes to the distro versions (e.g.
`1.18.0-6.1+deb11u10` on bullseye). This repo exists for hosts where the
distro package is not an option (features missing in 1.18, or suites like
stretch where ELTS carries no nginx security fixes at all).

## Repository layout

- `scripts/build.sh` - builds the package inside a `debian:<dist>`
  container (or matching host): fixes EOL apt sources, installs
  build-deps (stretch-backports debhelper where needed), runs
  `pkg-oss/debian make base`
- `docker/Dockerfile.<dist>` - local build environment per suite
- `.github/workflows/build-nginx.yml` - matrix build + publish to the
  `gh-pages` apt repo via `smeinecke/apt-repo-action`
- `add-repository.sh` - host-side repo setup (also installs Freexian
  ELTS - **required** on these EOL dists for base-system fixes)

## Usage on a host

```sh
wget -qO- https://greensec.github.io/build-nginx/add-repository.sh | sh
apt-get install nginx          # upgrades the nginx.org package in place
```

The published packages keep the nginx.org version scheme
(`1.30.7-1~stretch`), so they upgrade cleanly over
`1.30.5-1~bullseye`-style installs. The nginx.org list file
(`/etc/apt/sources.list.d/nginx*.list`) can be removed or pinned away
afterwards; it carries no newer builds for these suites anyway.

## Freexian ELTS is required

All supported suites are EOL. Base-system security fixes (openssl, zlib,
pcre...) only come via Freexian Extended LTS - `add-repository.sh`
installs it automatically. Hosts must have `stretch-lts`/`buster-lts`/
`bullseye-lts` enabled.

## Build

GitHub Actions -> `build nginx packages` -> pick `dist` (or `all`) and the
`pkg-oss` tag (default `1.30.7-1`), tick `release` to publish.

Locally:

```sh
DIST=stretch ./scripts/build.sh     # needs root, or run inside docker/Dockerfile.stretch
```

Built versions are tracked in [VERSIONS.md](VERSIONS.md).
