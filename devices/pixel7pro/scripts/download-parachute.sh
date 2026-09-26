#!/usr/bin/env bash
# Download restore images into parachute/. Does not flash anything.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/parachute"
mkdir -p "$DEST"
cd "$DEST"

# Matching this phone's Evolution X 10.3 / AP4A.250205.002
FACTORY_URL="https://dl.google.com/dl/android/aosp/cheetah-ap4a.250205.002-factory-6a87c591.zip"
FACTORY_SHA="6a87c591a5d6811a3b102a440743cbad8fdc10e553cd4df8906dccc6980afc7c"
FACTORY_ZIP="cheetah-ap4a.250205.002-factory-6a87c591.zip"

EVO_URL="https://sourceforge.net/projects/evolution-x/files/cheetah/15/EvolutionX-15.0-20250206-cheetah-10.3-Official.zip/download"
EVO_ZIP="EvolutionX-15.0-20250206-cheetah-10.3-Official.zip"

fetch() {
  local url="$1" out="$2"
  if [[ -f "$out" ]]; then
    echo "already have $out"
    return
  fi
  echo "GET $url -> $out"
  curl -fL --retry 5 --retry-all-errors -C - -o "$out.part" "$url"
  mv "$out.part" "$out"
}

fetch "$FACTORY_URL" "$FACTORY_ZIP"
echo "$FACTORY_SHA  $FACTORY_ZIP" | sha256sum -c -

echo "GET $EVO_URL -> $EVO_ZIP"
if [[ ! -f "$EVO_ZIP" ]]; then
  curl -fL --retry 5 --retry-all-errors -C - -o "$EVO_ZIP.part" "$EVO_URL"
  mv "$EVO_ZIP.part" "$EVO_ZIP"
fi
ls -lh "$DEST"
