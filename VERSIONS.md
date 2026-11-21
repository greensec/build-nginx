# Published nginx versions

Builds are produced from upstream [pkg-oss](https://github.com/nginx/pkg-oss)
tags and published to `https://greensec.github.io/build-nginx/repo`.

| suite | version | built | notes |
|---|---|---|---|
| jessie | `1.30.7-1~jessie` | 2026-11-21 | debhelper 9 compat; PCRE1; OpenSSL 1.0.1; no systemd unit (init script only); amd64+i386 |
| stretch | `1.30.7-1~stretch` | 2026-11-21 | debhelper via stretch-backports; OpenSSL 1.1.0 (no TLS 1.3/QUIC) |
| buster | `1.30.7-1~buster` | 2026-11-21 | no QUIC (OpenSSL 1.1.1) |
| bullseye | `1.30.7-1~bullseye` | 2026-11-21 | no QUIC (OpenSSL 1.1.1) |

## Fixes in 1.30.7 (NGINX2Root, 2026-11-18)

- CVE-2026-123633 - HTTP/2 use-after-free in reusable connection queue
- CVE-2026-123007 - HTTP/2 flow control memory corruption
- CVE-2026-123634 - resolver context use-after-free
- CVE-2026-113425 - mail session use-after-free
- CVE-2026-121810 - worker memory corruption
- CVE-2026-123640 - ssl_preread ClientHello validation
- CVE-2026-118899 - request body NGX_AGAIN handling
- CVE-2026-125283 - alias prefix try_files length
