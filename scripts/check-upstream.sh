#!/usr/bin/env bash
# Compare the latest nginx.org release against what our gh-pages repo serves
# for each supported suite.
#
# Exit codes: 0 all suites current, 1 behind/missing (a build is needed),
#             2 a fetch failed (upstream or repo Packages unreachable).
# When GITHUB_OUTPUT is set, also writes: latest=<ver>, behind=true|false,
# error=true|false - the check-upstream workflow uses them to dispatch a
# build and to decide whether a failing run (notification) is warranted.
#
# env: UPSTREAM_URL (nginx.org repo to read the newest stable release from),
#      REPO_URL (our published apt repo)

set -uo pipefail
: "${UPSTREAM_URL:=https://nginx.org/packages/debian/dists/bookworm/nginx/binary-amd64/Packages}"
: "${REPO_URL:=https://greensec.github.io/build-nginx/repo}"

SUITES="jessie stretch buster bullseye"
behind=0
error=0

emit() {
    if [ -n "${GITHUB_OUTPUT:-}" ]; then
        printf '%s\n' "$1" >>"$GITHUB_OUTPUT"
    fi
}

latest=$(curl -fsSL --max-time 15 "$UPSTREAM_URL" \
    | awk '$1 == "Package:" {pkg = $2} pkg == "nginx" && $1 == "Version:" {print $2}' \
    | cut -d- -f1 | sort -Vu | tail -1)
if [ -z "$latest" ]; then
    echo "could not fetch latest nginx.org release" >&2
    emit "error=true"
    exit 2
fi
echo "latest nginx.org release: $latest"
echo
echo "suite    repo-version          status"
for dist in $SUITES; do
    if ! pkgs=$(curl -fsSL --max-time 15 "$REPO_URL/dists/$dist/main/binary-amd64/Packages" 2>/dev/null); then
        printf "%-8s %-20s %s\n" "$dist" "?" "ERROR"
        error=1
        continue
    fi
    have=$(printf '%s\n' "$pkgs" \
        | awk '$1 == "Package:" {hit = ($2 == "nginx")} hit && $1 == "Version:" {print $2; exit}' \
        | cut -d- -f1)
    if [ -z "$have" ]; then
        printf "%-8s %-20s %s\n" "$dist" "none" "MISSING"
        behind=1
    elif dpkg --compare-versions "$have" lt "$latest"; then
        printf "%-8s %-20s %s\n" "$dist" "$have" "BEHIND"
        behind=1
    else
        printf "%-8s %-20s %s\n" "$dist" "$have" "ok"
    fi
done

emit "latest=$latest"
emit "behind=$([ "$behind" -eq 1 ] && echo true || echo false)"
emit "error=$([ "$error" -eq 1 ] && echo true || echo false)"

[ "$error" -eq 1 ] && exit 2
[ "$behind" -eq 1 ] && exit 1
exit 0
