#!/bin/zsh
# 用 -O 编译 App 搜索引擎源码 + Scripts/Benchmark/main.swift，运行基准测试并输出 Markdown 表格。
#
# 用法：
#   ./Scripts/benchmark.sh                     # 默认参数
#   ./Scripts/benchmark.sh --runs 3 --skip-volume
#   ./Scripts/benchmark.sh --tree-root ~/Projects --name readme --content-root ~/Projects --content TODO
#
# 结果同时写入 build/benchmark/result.md

set -euo pipefail

ROOT_DIR="${0:A:h:h}"
OUTPUT_DIR="$ROOT_DIR/build/benchmark"
BINARY="$OUTPUT_DIR/filehound-benchmark"
ENGINE="$ROOT_DIR/FileHound/SearchEngine"

SOURCES=(
  "$ROOT_DIR/Scripts/Benchmark/main.swift"
  "$ENGINE/Access/FilesystemAccessProviding.swift"
  "$ENGINE/Access/LocalFilesystemProvider.swift"
  "$ENGINE/Access/PrivilegedFilesystemProvider.swift"
  "$ENGINE/Access/VolumeCatalogSearcher.swift"
  "$ENGINE/Walker/DirectoryWalker.swift"
  "$ENGINE/Planner/SearchPlan.swift"
  "$ENGINE/Planner/SpecialFolderPlanner.swift"
  "$ENGINE/Query/QueryRule.swift"
  "$ENGINE/Query/SearchQuery.swift"
  "$ENGINE/Matching/ContentMatcher.swift"
  "$ROOT_DIR/FileHound/Modules/SearchRules/SearchRuleCatalog.swift"
)

# 默认的内容搜索目录：Xcode 自带 macOS SDK 的头文件，各机器上内容一致，便于复现
DEFAULT_ARGS=()
if [[ " $* " != *" --content-root "* ]]; then
  SDK_PATH="$(xcrun --sdk macosx --show-sdk-path 2>/dev/null || true)"
  if [[ -n "$SDK_PATH" && -d "$SDK_PATH/System/Library/Frameworks" ]]; then
    DEFAULT_ARGS+=(--content-root "$SDK_PATH/System/Library/Frameworks")
  fi
fi

mkdir -p "$OUTPUT_DIR"
echo "编译基准测试（-O）…" >&2
xcrun swiftc -O -swift-version 5 -module-name FileHoundBenchmark -o "$BINARY" "${SOURCES[@]}"

"$BINARY" "${DEFAULT_ARGS[@]}" "$@" | tee "$OUTPUT_DIR/result.md"
