#!/bin/bash
# Builds the Rust engine (crates/meowpuut-ffi) as a static library for
# HarmonyOS / OpenHarmony, and stages the lexicon assets into harmony/.
#
#   bash scripts/build-harmony.sh               -> .build/rust/harmony/<abi>/libmeowpuut_ffi.a
#   bash scripts/build-harmony.sh --prepare     -> the Rust engine and lexicon assets only
#                                                   (DevEco 的 preBuild 任务会调用这个)
#
# 需要：
#   - OpenHarmony SDK（OHOS_SDK，默认 $OHOS_SDK 或 ~/OpenHarmony/Sdk），
#     里面要有 native/llvm/bin/clang 和 native/sysroot；
#   - Rust，加上 aarch64-unknown-linux-ohos、x86_64-unknown-linux-ohos 两个 target
#     （armv7-unknown-linux-ohos 可选用 MEOWPUUT_OHOS_ABIS=arm64-v8a x86_64 关闭）。
#
# Rust 官方没有内置 ohos 的链接器，这里按照 rustc 平台文档生成 clang 包装脚本：
#   -target aarch64-linux-ohos --sysroot=<sysroot> -D__MUSL__
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
# 词库脚本读写 UTF-8 源文件；Windows 上 Python 默认用 GBK，必须强制。
export PYTHONUTF8=1
export PYTHONIOENCODING=utf-8
export PATH="$HOME/.cargo/bin:$PATH"
if ! command -v cargo >/dev/null; then
  echo "error: cargo not found. Install Rust from https://rustup.rs" >&2
  exit 1
fi

SDK="${OHOS_SDK:-${OHOS_SDK_HOME:-$HOME/OpenHarmony/Sdk}}"
LLVM="$SDK/native/llvm/bin"
SYSROOT="$SDK/native/sysroot"
if [ ! -x "$LLVM/clang" ] || [ ! -d "$SYSROOT" ]; then
  echo "error: OpenHarmony SDK not found at $SDK (need native/llvm/bin/clang and native/sysroot)" >&2
  echo "       set OHOS_SDK to the SDK directory" >&2
  exit 1
fi
# macOS 与 Linux 的 SDK 目录层级不同（mac 版 clang 在 native/llvm/bin，Linux 版在 native/llvm/bin）
# 两者都按上面的路径找；找不到就提示。
if ! command -v cmp >/dev/null; then
  echo "error: cmp not found" >&2
  exit 1
fi

ABIS="${MEOWPUUT_OHOS_ABIS:-arm64-v8a x86_64}"
# 生成 clang 包装脚本（一次，放进 .build/ohos-toolchain 以便重复使用）
wrap_dir="$ROOT/.build/ohos-toolchain"
mkdir -p "$wrap_dir"
make_wrapper() {
  local triple="$1" target="$2"
  local out="$wrap_dir/$triple-clang.sh"
  cat > "$out" <<EOF
#!/bin/sh
exec "$LLVM/clang" -target "$target" --sysroot="$SYSROOT" -D__MUSL__ "\$@"
EOF
  chmod +x "$out"
}

build_rust() {
  # Xcode 的 SDKROOT/LIBRARY_PATH 不能漏进来。
  unset SDKROOT LIBRARY_PATH
  local installed
  installed="$(rustup target list --installed)"
  for abi in $ABIS; do
    local triple target
    case "$abi" in
      arm64-v8a) triple=aarch64-unknown-linux-ohos; target=aarch64-linux-ohos ;;
      x86_64)    triple=x86_64-unknown-linux-ohos;  target=x86_64-linux-ohos ;;
      *) echo "error: unsupported ABI $abi" >&2; exit 2 ;;
    esac
    make_wrapper "$triple" "$target"
    if ! grep -qx "$triple" <<<"$installed"; then
      rustup target add "$triple"
    fi
    upper="$(echo "$triple" | tr '[:lower:]-' '[:upper:]_')"
    export "CARGO_TARGET_${upper}_LINKER=$wrap_dir/$triple-clang.sh"
    export "AR_${triple//-/_}=$LLVM/llvm-ar"
    cargo rustc --release -p meowpuut-ffi --target "$triple" --crate-type staticlib
    local out=".build/rust/harmony/$abi"
    mkdir -p "$out"
    if ! cmp -s "target/$triple/release/libmeowpuut_ffi.a" "$out/libmeowpuut_ffi.a"; then
      cp "target/$triple/release/libmeowpuut_ffi.a" "$out/libmeowpuut_ffi.a"
    fi
    echo "Rust engine: $out/libmeowpuut_ffi.a"
  done
}

# 键盘要读的词典：中文词库、词对表、日文词表（和 Android 同一份）。
LEXICON_FILES="mimo_base.bin mimo_pairs.bin mimo_en.bin native-japanese.tsv"
# compile-native-lexicon.py 会读的东西，用于判断是否需要重新编译。
LEXICON_SOURCES="DataSources Resources/Lexicon scripts/compile-native-lexicon.py scripts/mimo_pipeline.py scripts/mimo_binary.py scripts/mimo_pairs.py scripts/mimo_jp_compile.py scripts/mimo_jp_binary.py scripts/mimo_english.py scripts/mimo_en_binary.py scripts/japanese_readings.py scripts/ConvertScript.swift"

lexicon_current() {
  local file
  for file in $LEXICON_FILES; do
    [ -f "$1/$file" ] || return 1
    # shellcheck disable=SC2086
    [ -z "$(find $LEXICON_SOURCES -type f -newer "$1/$file" -print -quit)" ] || return 1
  done
}

stage_asset_dir() {
  local src="$1" dst="$2"
  mkdir -p "$dst"
  for file in $LEXICON_FILES; do
    cp "$src/$file" "$dst/$file"
  done
}

stage_assets() {
  local assets_dir="harmony/entry/src/main/resources/rawfile/lexicon"
  if lexicon_current "$assets_dir"; then
    echo "lexicon assets up to date"
  else
    # 用 iOS/Generated 里的快照；没有就自己编。
    local src="iOS/Generated"
    if ! lexicon_current "$src"; then
      mkdir -p ".build/harmony-lexicon"
      python_for_build scripts/compile-native-lexicon.py ".build/harmony-lexicon" "$(converter_path)"
      # 英文词库（新内核 MIMO-EN-1 格式，mimo_en_binary.py 独立生成）。
      python_for_build scripts/mimo_en_binary.py ".build/harmony-lexicon/mimo_en.bin"
      src=".build/harmony-lexicon"
    fi
    stage_asset_dir "$src" "$assets_dir"
    echo "lexicon assets staged to $assets_dir"
  fi
}

# Windows 上 python3 常常是 Microsoft Store 的占位程序（直接退出、无任何输出），
# 所以优先用 MEOWPUUT_PYTHON，其次 python3/python，最后回落到 python3。
python_for_build() {
  local exe
  if [ -n "${MEOWPUUT_PYTHON:-}" ]; then
    "$MEOWPUUT_PYTHON" "$@"
    return
  fi
  for exe in python3 python; do
    if command -v "$exe" >/dev/null && "$exe" -c "import sys" >/dev/null 2>&1; then
      "$exe" "$@"
      return
    fi
  done
  echo "error: 找不到可用的 Python（设置 MEOWPUUT_PYTHON）" >&2
  exit 1
}

# compile-native-lexicon.py 需要一个把行从 stdin 读入、再逐行输出的简繁转换器。
# macOS 上由 swiftc 编译 scripts/ConvertScript.swift；Windows 没有可用的
# 独立可执行文件，就传一个带引号的命令行 "python.exe" "convert-script.py"
# （compile-native-lexicon.py 的 converter_argv 会拆分它）。
converter_path() {
  # 新版 compile-native-lexicon.py 把 converter 当单个可执行文件
  # （subprocess.run([converter])）。macOS/Linux 用 swiftc 编出的二进制；
  # Windows 生成 .bat 包装器调 scripts/convert-script.py（OpenCC 版），
  # 并回显纯反斜杠 Windows 路径（cmd/ CreateProcess 才认）。
  local built="$ROOT/.build/convert-script"
  if command -v swiftc >/dev/null && [ -f scripts/ConvertScript.swift ]; then
    swiftc scripts/ConvertScript.swift -o "$built" >/dev/null 2>&1 && { echo "$built"; return; }
  fi
  local py
  py="${MEOWPUUT_PYTHON:-$(command -v python3 || command -v python)}"
  if [ -z "$py" ]; then
    echo "error: 需要一个 Python 解释器来编译词库（设置 MEOWPUUT_PYTHON）" >&2
    exit 1
  fi
  local bat="$ROOT/.build/convert-script.bat"
  mkdir -p "$ROOT/.build"
  if command -v cygpath >/dev/null; then
    local pyw batw scriptw
    pyw="$(cygpath -w "$py")"
    batw="$(cygpath -w "$bat")"
    scriptw="$(cygpath -w "$ROOT/scripts/convert-script.py")"
    printf '@echo off
"%s" "%s" %%*
' "$pyw" "$scriptw" > "$bat"
    echo "$batw"
  else
    printf '#!/bin/sh
exec "%s" "%s" "$@"
' "$py" "$ROOT/scripts/convert-script.py" > "$bat"
    chmod +x "$bat"
    echo "$bat"
  fi
}

# 猫咪与节日贴图（Resources/ 下的原图，保留版权，原样复制到 rawfile）。
stage_images() {
  local raw="harmony/entry/src/main/resources/rawfile"
  mkdir -p "$raw/cats"
  for f in Resources/Cats/*.png; do
    case "$f" in *@2x.png) continue ;; esac
    cp -n "$f" "$raw/cats/$(basename "$f")"
  done
  mkdir -p "$raw/festivals"
  for f in Resources/Festivals/*.png; do
    case "$f" in *@2x.png) continue ;; esac
    cp -n "$f" "$raw/festivals/$(basename "$f")"
  done
  # 节日清单。
  if [ -f "assets/festivals/festivals.json" ]; then
    cp -n "assets/festivals/festivals.json" "$raw/festivals/festivals.json"
  elif [ -f "Resources/Festivals/festivals.json" ]; then
    cp -n "Resources/Festivals/festivals.json" "$raw/festivals/festivals.json"
  fi

  # 应用/输入法图标：优先用原图标，缺省提示自行放置。
  local media="harmony/entry/src/main/resources/base/media"
  local appmedia="harmony/AppScope/resources/base/media"
  mkdir -p "$media" "$appmedia"
  if [ -f "Android/app/src/main/res/drawable-nodpi/ic_launcher_foreground.png" ] && [ ! -f "$media/icon.png" ]; then
    cp "Android/app/src/main/res/drawable-nodpi/ic_launcher_foreground.png" "$media/icon.png"
    cp "Android/app/src/main/res/drawable-nodpi/ic_launcher_foreground.png" "$appmedia/app_icon.png"
    echo "icon staged from ic_launcher_foreground.png"
  elif [ ! -f "$media/icon.png" ]; then
    echo "warn: no icon at $media/icon.png; place a 108x108 (or larger) PNG manually"
  fi

  echo "cat/festival images staged to $raw"
}

mode="${1:-debug}"
case "$mode" in
  debug|--prepare) ;;
  *) echo "usage: bash scripts/build-harmony.sh [--prepare]" >&2; exit 2 ;;
esac

build_rust
stage_assets
stage_images