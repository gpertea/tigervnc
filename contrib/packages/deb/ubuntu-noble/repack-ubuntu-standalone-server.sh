#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 UBUNTU_SERVER_DEB UPSTREAM_SERVER_DEB OUTPUT_DEB" >&2
  exit 2
}

[[ $# -eq 3 ]] || usage

base_deb="$(readlink -f -- "$1")"
upstream_deb="$(readlink -f -- "$2")"
output_deb="$(readlink -m -- "$3")"
version="${VERSION:-1.16.2+gpertea2}"

[[ "$(dpkg-deb -f "$base_deb" Package)" == "tigervnc-standalone-server" ]] || {
  echo "error: base package is not tigervnc-standalone-server" >&2
  exit 1
}
[[ "$(dpkg-deb -f "$upstream_deb" Package)" == "tigervncserver" ]] || {
  echo "error: upstream package is not tigervncserver" >&2
  exit 1
}
[[ "$version" =~ ^[A-Za-z0-9.+:~_-]+$ ]] || {
  echo "error: invalid package version: $version" >&2
  exit 1
}

work="$(mktemp -d)"
trap 'rm -rf -- "$work"' EXIT

mkdir -p "$work/root" "$work/upstream"
dpkg-deb -x "$base_deb" "$work/root"
dpkg-deb -e "$base_deb" "$work/root/DEBIAN"
dpkg-deb -x "$upstream_deb" "$work/upstream"

install -m 0755 "$work/upstream/usr/bin/Xtigervnc" \
  "$work/root/usr/bin/Xtigervnc"
install -m 0755 "$work/upstream/usr/bin/tigervncconfig" \
  "$work/root/usr/bin/tigervncconfig"
if [[ -f "$work/upstream/usr/share/man/man1/Xtigervnc.1.gz" ]]; then
  install -m 0644 "$work/upstream/usr/share/man/man1/Xtigervnc.1.gz" \
    "$work/root/usr/share/man/man1/Xtigervnc.1.gz"
fi

python3 - "$work/root/DEBIAN/control" "$version" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
version = sys.argv[2]
control = path.read_text()
control = re.sub(r"^Version:.*$", f"Version: {version}", control, flags=re.M)

extra = [
    "libgbm1 (>= 17.3.0~rc1)",
    "libxcvt0 (>= 0.1.0)",
    "libxshmfence1",
    "libx11-6 (>= 2:1.4.99.1)",
    "libxext6",
]
match = re.search(r"^Depends: (.*)$", control, flags=re.M)
if not match:
    raise SystemExit("Depends field not found")
depends = match.group(1)
for dependency in extra:
    if dependency.split()[0] not in depends:
        depends += ", " + dependency
control = control[:match.start(1)] + depends + control[match.end(1):]
control = control.replace(
    "Description: ",
    "Description: TigerVNC 1.16.2 local rebuild - ",
    1,
)
path.write_text(control)
PY

add_script_prefix() {
  local name="$1"
  local body="$2"
  local original="$work/root/DEBIAN/${name}"
  local replacement="$work/root/DEBIAN/${name}.new"

  {
    echo '#!/bin/sh'
    echo 'set -e'
    printf '%s\n' "$body"
    if [[ -f "$original" ]]; then
      sed '1{/^#!\/bin\/sh$/d;}' "$original"
    fi
  } > "$replacement"
  chmod 0755 "$replacement"
  mv -f -- "$replacement" "$original"
}

add_script_prefix preinst '
dpkg-divert --package tigervnc-standalone-server \
  --add --rename \
  --divert /usr/bin/tigervncconfig.ubuntu-1.13 \
  /usr/bin/tigervncconfig
'

add_script_prefix postrm '
case "$1" in
  remove|abort-install|disappear)
    if dpkg-divert --list /usr/bin/tigervncconfig | grep -q .; then
      dpkg-divert --package tigervnc-standalone-server \
        --remove --rename \
        --divert /usr/bin/tigervncconfig.ubuntu-1.13 \
        /usr/bin/tigervncconfig
    fi
    ;;
esac
'

(
  cd "$work/root"
  find . -path ./DEBIAN -prune -o -type f -printf '%P\0' |
    sort -z |
    xargs -0 -r md5sum > DEBIAN/md5sums
)

mkdir -p "$(dirname -- "$output_deb")"
dpkg-deb --root-owner-group --build "$work/root" "$output_deb" >/dev/null
dpkg-deb -f "$output_deb" Package Version Architecture
sha256sum "$output_deb"
