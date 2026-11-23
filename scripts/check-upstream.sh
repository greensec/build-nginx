#!/usr/bin/env bash
# Compare the latest nginx.org release against what our gh-pages repo serves
# for each supported suite. Exit 1 (cron failure -> notification) when any
# suite is behind or missing.
#
# env: UPSTREAM_URL (nginx.org repo to read the newest stable release from),
#      REPO_URL (our published apt repo)

set -uo pipefail
: "${UPSTREAM_URL:=https://nginx.org/packages/debian/dists/bookworm/nginx/binary-amd64/Packages}"
: "${REPO_URL:=https://greensec.github.io/build-nginx/repo}"

SUITES="jessie stretch buster bullseye"
fail=0

latest=$(curl -fsSL --max-time 15 "$UPSTREAM_URL" \
    | awk '$1 == "Package:" {pkg = $2} pkg == "nginx" && $1 == "Version:" {print $2}' \
    | cut -d- -f1 | sort -Vu | tail -1)
if [ -z "$latest" ]; then
    echo "could not fetch latest nginx.org release" >&2
    exit 1
fi
echo "latest nginx.org release: $latest"
echo
echo "suite    repo-version          status"
for dist in $SUITES; do
    have=$(curl -fsSL --max-time 15 "$REPO_URL/dists/$dist/main/binary-amd64/Packages" 2>/dev/null \
        | awk '$1 == "Package:" {hit = ($2 == "nginx")} hit && $1 == "Version:" {print $2; exit}' \
        | cut -d- -f1)
    if [ -z "$have" ]; then
        printf "%-8s %-20s %s\n" "$dist" "none" "MISSING"
        fail=1
    elif dpkg --compare-versions "$have" lt "$latest"; then
        printf "%-8s %-20s %s\n" "$dist" "$have" "BEHIND"
        fail=1
    else
        printf "%-8s %-20s %s\n" "$dist" "$have" "ok"
    fi
done
exit $fail
