#!/bin/sh
set -euo pipefail

SOURCE_BIN="/opt/homebrew/bin/llama-server"
if [ ! -x "$SOURCE_BIN" ]; then
  SOURCE_BIN="/usr/local/bin/llama-server"
fi
if [ ! -x "$SOURCE_BIN" ]; then
  if [ "${ATLAS_ALLOW_EXTERNAL_RUNTIME_FALLBACK:-0}" = "1" ]; then
    echo "warning: llama-server binary not found on build machine; external runtime fallback explicitly allowed"
    exit 0
  fi
  echo "error: llama-server binary not found on build machine; refusing to produce an app that depends on an external runtime"
  exit 1
fi

HELPER_BUNDLE_ID="com.atlasmasa.macos.local-ai-runtime"
HELPER_APP_NAME="BlackHavenLocalAI"
HELPER_EXECUTABLE_NAME="BlackHaven"
HELPER_APP_DIR="${TARGET_BUILD_DIR}/${CONTENTS_FOLDER_PATH}/Helpers/${HELPER_APP_NAME}.app"
HELPER_CONTENTS_DIR="$HELPER_APP_DIR/Contents"
HELPER_MACOS_DIR="$HELPER_CONTENTS_DIR/MacOS"
HELPER_FRAMEWORKS_DIR="$HELPER_CONTENTS_DIR/Frameworks"
HELPER_RESOURCES_DIR="$HELPER_CONTENTS_DIR/Resources"
HELPER_INFO_PLIST="$HELPER_CONTENTS_DIR/Info.plist"
DEST_DIR="$HELPER_FRAMEWORKS_DIR"
DEST_BIN="$HELPER_MACOS_DIR/${HELPER_EXECUTABLE_NAME}"
LEGACY_RUNTIME_DIR="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/LocalAIRuntime"
MODEL_DEST_NAME="${ATLAS_LLM_BUNDLED_MODEL_FILE:-Qwen2.5-7B-Instruct-Q4_K_M.gguf}"
MODEL_SOURCE_PATH="${ATLAS_LLM_BUNDLED_MODEL_PATH:-}"
SOURCE_PREFIX="$(cd "$(dirname "$SOURCE_BIN")/.." && pwd)"
SOURCE_LIB_DIR="$SOURCE_PREFIX/lib"
RESOURCE_DIR="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}"

rm -rf "$HELPER_APP_DIR" "$LEGACY_RUNTIME_DIR"
mkdir -p "$HELPER_MACOS_DIR" "$HELPER_FRAMEWORKS_DIR" "$HELPER_RESOURCES_DIR"
cp -f "$SOURCE_BIN" "$DEST_BIN"
chmod 755 "$DEST_BIN"

cat >"$HELPER_INFO_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleExecutable</key>
	<string>${HELPER_EXECUTABLE_NAME}</string>
	<key>CFBundleIdentifier</key>
	<string>${HELPER_BUNDLE_ID}</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleDisplayName</key>
	<string>BlackHaven</string>
	<key>CFBundleName</key>
	<string>BlackHaven</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>LSBackgroundOnly</key>
	<true/>
</dict>
</plist>
EOF

if [ -n "$MODEL_SOURCE_PATH" ] && [ -f "$MODEL_SOURCE_PATH" ]; then
  mkdir -p "$RESOURCE_DIR"
  cp -f "$MODEL_SOURCE_PATH" "$RESOURCE_DIR/$MODEL_DEST_NAME"
elif [ "${ATLAS_ALLOW_EXTERNAL_MODEL_FALLBACK:-0}" = "1" ]; then
  echo "warning: bundled model not provided; external model fallback explicitly allowed"
else
  echo "warning: bundled model not provided; app will rely on in-app Qwen download/cache on first launch"
fi

DEPENDENCY_NAMES="$(otool -L "$SOURCE_BIN" | awk '/@rpath\/lib(llama|ggml|mtmd)/ { sub("@rpath/", "", $1); print $1 }')"
OPENSSL_DEP_PATHS="$(otool -L "$SOURCE_BIN" | awk '/openssl@3\/.*\/lib\/libssl\.3\.dylib|openssl@3\/.*\/lib\/libcrypto\.3\.dylib/ { print $1 }')"
if [ -z "$OPENSSL_DEP_PATHS" ]; then
  for fallback in \
    "/opt/homebrew/opt/openssl@3/lib/libssl.3.dylib" \
    "/opt/homebrew/opt/openssl@3/lib/libcrypto.3.dylib" \
    "/usr/local/opt/openssl@3/lib/libssl.3.dylib" \
    "/usr/local/opt/openssl@3/lib/libcrypto.3.dylib"
  do
    if [ -f "$fallback" ]; then
      OPENSSL_DEP_PATHS="${OPENSSL_DEP_PATHS:+$OPENSSL_DEP_PATHS }$fallback"
    fi
  done
fi

copy_dep() {
  lib_name="$1"
  src="$SOURCE_LIB_DIR/$lib_name"
  dest="$DEST_DIR/$lib_name"
  if [ ! -f "$src" ]; then
    echo "warning: dependent library missing: $src"
    return
  fi
  cp -f "$src" "$dest"
  chmod 755 "$dest"
  install_name_tool -id "@rpath/$lib_name" "$dest" >/dev/null 2>&1 || true
}

copy_dep_path() {
  src="$1"
  lib_name="$(basename "$src")"
  dest="$DEST_DIR/$lib_name"
  if [ ! -f "$src" ]; then
    echo "warning: dependent library missing: $src"
    return
  fi
  cp -f "$src" "$dest"
  chmod 755 "$dest"
  install_name_tool -id "@rpath/$lib_name" "$dest" >/dev/null 2>&1 || true
}

for lib_name in $DEPENDENCY_NAMES; do
  copy_dep "$lib_name"
done

for dep_path in $OPENSSL_DEP_PATHS; do
  copy_dep_path "$dep_path"
done

install_name_tool -add_rpath "@loader_path/../Frameworks" "$DEST_BIN" >/dev/null 2>&1 || true
for lib_name in $DEPENDENCY_NAMES; do
  install_name_tool -change "@rpath/$lib_name" "@loader_path/../Frameworks/$lib_name" "$DEST_BIN" >/dev/null 2>&1 || true
done
for dep_path in $OPENSSL_DEP_PATHS; do
  lib_name="$(basename "$dep_path")"
  install_name_tool -change "$dep_path" "@loader_path/../Frameworks/$lib_name" "$DEST_BIN" >/dev/null 2>&1 || true
done

if otool -L "$DEST_BIN" | grep -q 'openssl@3/.*/lib/libssl\.3\.dylib\|openssl@3/.*/lib/libcrypto\.3\.dylib'; then
  echo "error: embedded llama-server still depends on external OpenSSL dylibs"
  exit 1
fi

for lib_name in $DEPENDENCY_NAMES; do
  dest="$DEST_DIR/$lib_name"
  [ -f "$dest" ] || continue
  for inner_dep in $DEPENDENCY_NAMES; do
    install_name_tool -change "@rpath/$inner_dep" "@loader_path/$inner_dep" "$dest" >/dev/null 2>&1 || true
  done
done

for dep_path in $OPENSSL_DEP_PATHS; do
  dest="$DEST_DIR/$(basename "$dep_path")"
  [ -f "$dest" ] || continue
  for inner_dep in $DEPENDENCY_NAMES; do
    install_name_tool -change "@rpath/$inner_dep" "@loader_path/$inner_dep" "$dest" >/dev/null 2>&1 || true
  done
  dylib_openssl_deps="$(otool -L "$dest" | awk '/openssl@3\/.*\/lib\/libssl\.3\.dylib|openssl@3\/.*\/lib\/libcrypto\.3\.dylib/ { print $1 }')"
  for other_openssl_dep in $dylib_openssl_deps; do
    other_name="$(basename "$other_openssl_dep")"
    install_name_tool -change "$other_openssl_dep" "@loader_path/$other_name" "$dest" >/dev/null 2>&1 || true
  done
done

codesign_path() {
  target="$1"
  entitlements_file="${2:-}"
  identifier="${3:-}"
  identifier_args=""
  if [ -n "$identifier" ]; then
    identifier_args="--identifier $identifier"
  fi
  if [ "${CODE_SIGNING_ALLOWED:-NO}" = "YES" ] && [ -n "${EXPANDED_CODE_SIGN_IDENTITY:-}" ]; then
    if [ -n "$entitlements_file" ] && [ -f "$entitlements_file" ]; then
      /usr/bin/codesign --force --sign "$EXPANDED_CODE_SIGN_IDENTITY" $identifier_args --entitlements "$entitlements_file" "$target"
    else
      /usr/bin/codesign --force --sign "$EXPANDED_CODE_SIGN_IDENTITY" $identifier_args "$target"
    fi
  else
    if [ -n "$entitlements_file" ] && [ -f "$entitlements_file" ]; then
      /usr/bin/codesign --force --sign - $identifier_args --entitlements "$entitlements_file" "$target"
    else
      /usr/bin/codesign --force --sign - $identifier_args "$target"
    fi
  fi
}

for lib_name in $DEPENDENCY_NAMES; do
  dest="$DEST_DIR/$lib_name"
  [ -f "$dest" ] || continue
  codesign_path "$dest"
done
for dep_path in $OPENSSL_DEP_PATHS; do
  dest="$DEST_DIR/$(basename "$dep_path")"
  [ -f "$dest" ] || continue
  codesign_path "$dest"
done
RUNTIME_ENTITLEMENTS_FILE="${SRCROOT}/AtlasMasaMacOS/LocalAIRuntime.entitlements"
codesign_path "$HELPER_APP_DIR" "$RUNTIME_ENTITLEMENTS_FILE" "$HELPER_BUNDLE_ID"

if command -v dsymutil >/dev/null 2>&1 && [ -n "${DWARF_DSYM_FOLDER_PATH:-}" ]; then
  mkdir -p "${DWARF_DSYM_FOLDER_PATH}"
  for lib_name in $DEPENDENCY_NAMES; do
    dest="$DEST_DIR/$lib_name"
    [ -f "$dest" ] || continue
    /usr/bin/dsymutil "$dest" -o "${DWARF_DSYM_FOLDER_PATH}/${lib_name}.dSYM" || true
  done
  for dep_path in $OPENSSL_DEP_PATHS; do
    lib_name="$(basename "$dep_path")"
    dest="$DEST_DIR/$lib_name"
    [ -f "$dest" ] || continue
    /usr/bin/dsymutil "$dest" -o "${DWARF_DSYM_FOLDER_PATH}/${lib_name}.dSYM" || true
  done
  /usr/bin/dsymutil "$DEST_BIN" -o "${DWARF_DSYM_FOLDER_PATH}/${HELPER_APP_NAME}-${HELPER_EXECUTABLE_NAME}.dSYM" || true
fi

if otool -L "$DEST_BIN" | grep -q "libggml-metal"; then
  echo "Embedded llama-server with Metal runtime dependencies"
else
  echo "warning: embedded llama-server does not reference libggml-metal"
fi
