#!/bin/sh
set -e
ROOT=$(cd "$(dirname "$0")" && pwd)
OUT=${1:-$ROOT/dist}
VER=$(sed -n 's/^version=//p' "$ROOT/module/module.prop")
NAME="FCM-Keeper-For-HyperOS-$VER.zip"
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
cp -R "$ROOT/module/." "$STAGE/"
cp "$ROOT/README.md" "$STAGE/README.md"
find "$STAGE" -type f -exec sed -i 's/\r$//' {} +
find "$STAGE" -type d -exec chmod 755 {} +
find "$STAGE" -type f -exec chmod 644 {} +
chmod 755 "$STAGE"/*.sh "$STAGE"/bin/* "$STAGE"/lib/*.sh
find "$STAGE" -exec touch -h -d '2026-01-01 00:00:00 UTC' {} +
mkdir -p "$OUT"
rm -f "$OUT/$NAME"
( cd "$STAGE" && find . -type f | sed 's|^\./||' | LC_ALL=C sort | zip -X -q -@ "$OUT/$NAME" )
( cd "$OUT" && sha256sum "$NAME" > "$NAME.sha256" )
echo "$OUT/$NAME"
cat "$OUT/$NAME.sha256"
