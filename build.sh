#!/bin/bash
# Собирает cloudet, прогоняет проверки и, по флагу, упаковывает .dmg.
#   ./build.sh            собрать и запустить
#   ./build.sh --test     ещё и проверить имена, размеры и индекс
#   ./build.sh --dmg      универсальный .dmg в dist/, без подписи и без запуска
set -euo pipefail
cd "$(dirname "$0")"

TEST=0
DMG=0
LAUNCH=1
UNIVERSAL=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --test) TEST=1 ;;
    --dmg) DMG=1; LAUNCH=0; UNIVERSAL=1 ;;
    --no-launch) LAUNCH=0 ;;
    --universal) UNIVERSAL=1 ;;
    *)
      echo "Неизвестный аргумент: $1" >&2
      exit 1
      ;;
  esac
  shift
done

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
SWIFTC="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc"
SDK="$DEVELOPER_DIR/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"
if [[ ! -x "$SWIFTC" ]]; then
  echo "Нужен установленный Xcode." >&2
  exit 1
fi

APP="build/cloudet drag'n'drop.app"
DEPLOYMENT=14.0
VERSION="${CLOUDET_VERSION:-1.0}"
VERSION="${VERSION#v}"
BUILD_NUMBER="${CLOUDET_BUILD:-1}"

compile() {
  local arch="$1"
  local output="$2"
  shift 2
  "$SWIFTC" -swift-version 5 -parse-as-library -wmo \
    -target "${arch}-apple-macosx${DEPLOYMENT}" \
    -sdk "$SDK" \
    -framework AppKit \
    -framework ImageIO \
    -framework SwiftUI \
    -o "$output" \
    "$@"
}

run_tests() {
  mkdir -p build
  local sources=()
  local file
  for file in Sources/*.swift; do
    [[ "$(basename "$file")" == "main.swift" ]] && continue
    sources+=("$file")
  done
  compile arm64 build/cloudet-tests "${sources[@]}" Tests/AppTests.swift
  ./build/cloudet-tests
}

stage_app() {
  rm -rf "$APP"
  mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
  local arches=(arm64)
  if [[ "$UNIVERSAL" -eq 1 ]]; then
    arches=(arm64 x86_64)
  fi
  local slices=()
  local arch
  for arch in "${arches[@]}"; do
    local slice="$APP/Contents/MacOS/cloudet-$arch"
    compile "$arch" "$slice" Sources/*.swift
    slices+=("$slice")
  done
  if [[ "${#slices[@]}" -eq 1 ]]; then
    mv "${slices[0]}" "$APP/Contents/MacOS/cloudet"
  else
    lipo -create "${slices[@]}" -output "$APP/Contents/MacOS/cloudet"
    rm -f "${slices[@]}"
  fi

  cp Info.plist "$APP/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP/Contents/Info.plist"
  printf 'APPL????' > "$APP/Contents/PkgInfo"

  mkdir -p Resources
  shopt -s nullglob
  local loc
  for loc in Resources/*.lproj; do
    cp -R "$loc" "$APP/Contents/Resources/"
  done

  compile arm64 build/makeicon Sources/CloudShape.swift tools/makeicon.swift
  ./build/makeicon "Resources/AppIcon.icns"
  cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
  if [[ "$UNIVERSAL" -eq 1 ]]; then
    lipo -info "$APP/Contents/MacOS/cloudet"
  fi
}

make_dmg() {
  mkdir -p dist
  local stage
  stage="$(mktemp -d)"
  ditto "$APP" "$stage/cloudet drag'n'drop.app"
  ln -s /Applications "$stage/Applications"
  local output="dist/cloudet-${VERSION}.dmg"
  rm -f "$output"
  # hdiutil на новых macOS помечен устаревшим, на старых runner его замена ещё не везде есть.
  if ! diskutil image create from --format UDZO --volumeName "cloudet" "$stage" "$output"; then
    rm -f "$output"
    hdiutil create \
      -volname "cloudet" \
      -srcfolder "$stage" \
      -ov \
      -format UDZO \
      "$output" >/dev/null
  fi
  rm -rf "$stage"
  echo "Собрано: $output"
}

if [[ "$TEST" -eq 1 ]]; then
  run_tests
fi

if [[ "$TEST" -eq 1 && "$DMG" -eq 0 && "$LAUNCH" -eq 0 ]]; then
  exit 0
fi

stage_app

if [[ "$DMG" -eq 1 ]]; then
  make_dmg
fi

if [[ "$LAUNCH" -eq 1 ]]; then
  codesign --force --sign - "$APP" >/dev/null
  pkill -x DropyCopy 2>/dev/null || true
  pkill -x Whisp 2>/dev/null || true
  pkill -x cloudet 2>/dev/null || true
  sleep 0.3
  open "$APP"
  echo "Запущено: $APP"
fi
