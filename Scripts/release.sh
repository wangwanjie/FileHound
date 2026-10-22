#!/usr/bin/env bash
#
# 一键发布 FileHound 双架构版本：
#   预检 → 并行构建 arm64 / x86_64 并公证 → 校验产物 → 创建草稿 Release 并上传
#   → 生成两份分架构 appcast 并同步旧版通用 appcast.xml → 校验 appcast
#   → 正式发布 Release → 提交并推送 appcast
#
# 先发布 Release 再推送 appcast：反过来的话，用户会先读到新 appcast，下载链接却还是 404。
#
# 用法:
#   ./Scripts/release.sh --notes-file docs/release-notes/v1.3.0.md [--skip-build] [--no-push] [--yes]
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PBXPROJ="$ROOT_DIR/FileHound.xcodeproj/project.pbxproj"
DMG_DIR="$ROOT_DIR/build/dmg"
LOG_DIR="$ROOT_DIR/build/release-logs"
ARCHS=(arm64 x86_64)

NOTES_FILE=""
SKIP_BUILD=false
SHOULD_PUSH=true
ASSUME_YES=false
REPO=""

usage() {
    cat <<'EOF'
用法:
  ./Scripts/release.sh --notes-file FILE [--repo OWNER/REPO] [--skip-build] [--no-push] [--yes]

选项:
  --notes-file FILE   本次版本的发布说明（Markdown），同时用于 GitHub Release 与两份 appcast
  --repo OWNER/REPO   GitHub 仓库，默认从 git remote 推断
  --skip-build        跳过构建，直接使用 build/dmg/ 下当前版本的两个 DMG（用于构建成功后续跑）
  --no-push           只在本地提交 appcast，不推送，Release 保持草稿状态
  --yes               跳过发布前的确认提示
  -h, --help          显示帮助

前置条件:
  - 已在 project.yml 更新 MARKETING_VERSION / CURRENT_PROJECT_VERSION 并执行 xcodegen generate
  - 工作区干净，位于 main 分支且与 origin/main 同步
  - gh auth login、notarytool profile、Keychain 中的 Sparkle 私钥均已就绪（见 README「打包」）
EOF
}

fail() {
    echo "错误: $*" >&2
    exit 1
}

step() {
    echo
    echo "==> $*"
}

read_project_setting() {
    sed -n "s/.*$1 = \\([^;]*\\);/\\1/p" "$PBXPROJ" | head -1 | tr -d ' '
}

detect_repo() {
    local remote_url
    remote_url="$(git -C "$ROOT_DIR" remote get-url origin 2>/dev/null || true)"
    if [[ "$remote_url" =~ github\.com[:/]([^/]+)/([^/]+)$ ]]; then
        printf '%s/%s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]%.git}"
        return 0
    fi
    return 1
}

# 两份分架构 appcast 中已发布的最大构建号
max_published_build() {
    /usr/bin/python3 - "$ROOT_DIR"/appcast-*.xml <<'PY'
import sys
import xml.etree.ElementTree as ET
ns = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"
best = 0
for path in sys.argv[1:]:
    for node in ET.parse(path).getroot().iter(f"{ns}version"):
        try:
            best = max(best, int((node.text or "0").strip()))
        except ValueError:
            pass
print(best)
PY
}

# 用 App 内置的 SUPublicEDKey 离线校验 EdDSA 签名，与 App 实际校验更新包的方式一致。
# 不用 sign_update --verify：它会访问钥匙串，无人值守时可能卡在授权弹窗上
verify_ed_signature() {
    python3 - "$1" "$2" "$SPARKLE_PUBLIC_KEY" <<'PY'
import base64
import sys
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey

path, signature, public_key = sys.argv[1:4]
with open(path, "rb") as handle:
    data = handle.read()
Ed25519PublicKey.from_public_bytes(base64.b64decode(public_key)).verify(base64.b64decode(signature), data)
PY
}

# 输出 appcast 中指定 DMG 的「length edSignature」
enclosure_info() {
    /usr/bin/python3 - "$1" "$2" <<'PY'
import sys
import xml.etree.ElementTree as ET
ns = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"
for enclosure in ET.parse(sys.argv[1]).getroot().iter("enclosure"):
    if enclosure.get("url", "").endswith("/" + sys.argv[2]):
        print(enclosure.get("length", ""), enclosure.get(f"{ns}edSignature", ""))
        break
else:
    raise SystemExit(f"{sys.argv[1]} 中没有 {sys.argv[2]}")
PY
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --notes-file)
            [[ -n "${2:-}" && "${2:-}" != --* ]] || fail "--notes-file 需要指定文件"
            NOTES_FILE="$2"
            shift 2
            ;;
        --repo)
            [[ -n "${2:-}" && "${2:-}" != --* ]] || fail "--repo 需要指定 OWNER/REPO"
            REPO="$2"
            shift 2
            ;;
        --skip-build)
            SKIP_BUILD=true
            shift
            ;;
        --no-push)
            SHOULD_PUSH=false
            shift
            ;;
        --yes)
            ASSUME_YES=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            usage >&2
            fail "未知参数 $1"
            ;;
    esac
done

cd "$ROOT_DIR"

[[ -n "$NOTES_FILE" ]] || fail "必须通过 --notes-file 指定发布说明"
[[ -f "$NOTES_FILE" ]] || fail "未找到发布说明: $NOTES_FILE"
NOTES_FILE="$(cd "$(dirname "$NOTES_FILE")" && pwd)/$(basename "$NOTES_FILE")"

if [[ -z "$REPO" ]]; then
    REPO="$(detect_repo)" || fail "无法从 git remote 推断 GitHub 仓库，请使用 --repo"
fi

VERSION="$(read_project_setting MARKETING_VERSION)"
BUILD_NUMBER="$(read_project_setting CURRENT_PROJECT_VERSION)"
TAG="v$VERSION"
[[ -n "$VERSION" && -n "$BUILD_NUMBER" ]] || fail "无法从工程读取版本号"

# ---------- 预检 ----------
step "预检 $TAG（build $BUILD_NUMBER）"

command -v gh >/dev/null 2>&1 || fail "未找到 gh"
gh auth status >/dev/null 2>&1 || fail "GitHub CLI 未登录，请先执行 gh auth login"

[[ "$(git rev-parse --abbrev-ref HEAD)" == "main" ]] || fail "请在 main 分支上发布"
[[ -z "$(git status --porcelain --untracked-files=no)" ]] || fail "工作区有未提交的改动"

git fetch --quiet origin main
[[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main)" ]] || fail "本地 main 与 origin/main 不同步，请先 push / pull"

spec_version="$(sed -n 's/^[[:space:]]*MARKETING_VERSION:[[:space:]]*//p' project.yml | head -1 | tr -d ' "')"
spec_build="$(sed -n 's/^[[:space:]]*CURRENT_PROJECT_VERSION:[[:space:]]*//p' project.yml | head -1 | tr -d ' "')"
[[ "$spec_version" == "$VERSION" && "$spec_build" == "$BUILD_NUMBER" ]] || fail "project.yml 与 project.pbxproj 的版本号不一致，请先执行 xcodegen generate"

published_build="$(max_published_build)"
[[ "$BUILD_NUMBER" -gt "$published_build" ]] || fail "构建号 $BUILD_NUMBER 必须大于 appcast 中已发布的最大构建号 $published_build"

if git ls-remote --exit-code --tags origin "refs/tags/$TAG" >/dev/null 2>&1; then
    remote_tag_commit="$(git ls-remote --tags origin "refs/tags/$TAG^{}" | awk '{print $1}')"
    if [[ -z "$remote_tag_commit" ]]; then
        remote_tag_commit="$(git ls-remote --tags origin "refs/tags/$TAG" | awk '{print $1}')"
    fi
    [[ "$remote_tag_commit" == "$(git rev-parse HEAD)" ]] || fail "远端已存在 tag $TAG 且不指向当前 HEAD"
fi

echo "仓库: $REPO"
echo "版本: $VERSION（build $BUILD_NUMBER），上一个已发布构建号: $published_build"
echo "提交: $(git rev-parse --short HEAD)"
echo "说明: $NOTES_FILE"

if [[ "$ASSUME_YES" != true ]]; then
    read -r -p "确认发布？[y/N] " answer
    [[ "$answer" == "y" || "$answer" == "Y" ]] || fail "已取消"
fi

# ---------- 构建 ----------
DMG_PATHS=()
for arch in "${ARCHS[@]}"; do
    DMG_PATHS+=("$DMG_DIR/FileHound_v${VERSION}_${BUILD_NUMBER}_${arch}.dmg")
done

if [[ "$SKIP_BUILD" != true ]]; then
    step "并行构建并公证 ${ARCHS[*]}（日志: $LOG_DIR）"
    mkdir -p "$LOG_DIR"
    pids=()
    for arch in "${ARCHS[@]}"; do
        "$SCRIPT_DIR/build_dmg.sh" --arch "$arch" > "$LOG_DIR/build-$arch.log" 2>&1 &
        pids+=("$!")
    done

    build_failed=false
    for index in "${!ARCHS[@]}"; do
        if wait "${pids[$index]}"; then
            echo "${ARCHS[$index]}: 构建成功"
        else
            echo "${ARCHS[$index]}: 构建失败，日志末尾：" >&2
            tail -30 "$LOG_DIR/build-${ARCHS[$index]}.log" >&2
            build_failed=true
        fi
    done
    [[ "$build_failed" == false ]] || fail "构建失败"
fi

# ---------- 校验 DMG ----------
step "校验 DMG"
for index in "${!ARCHS[@]}"; do
    arch="${ARCHS[$index]}"
    dmg_path="${DMG_PATHS[$index]}"
    [[ -f "$dmg_path" ]] || fail "未找到 $dmg_path"
    xcrun stapler validate "$dmg_path" >/dev/null || fail "$dmg_path 未完成公证 staple"

    # 挂载 DMG，检查其中 App 的架构、版本号和更新源
    mount_point="$(mktemp -d "${TMPDIR:-/tmp}/filehound-verify.XXXXXX")"
    hdiutil attach -nobrowse -readonly -mountpoint "$mount_point" "$dmg_path" >/dev/null
    app_path="$mount_point/FileHound.app"
    verify_error=""
    if [[ ! -d "$app_path" ]]; then
        verify_error="DMG 中没有 FileHound.app"
    else
        app_archs="$(lipo -archs "$app_path/Contents/MacOS/FileHound")"
        app_build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app_path/Contents/Info.plist")"
        app_feed="$(/usr/libexec/PlistBuddy -c 'Print :SUFeedURL' "$app_path/Contents/Info.plist")"
        if [[ "$app_archs" != "$arch" ]]; then
            verify_error="App 架构为 $app_archs，应为 $arch"
        elif [[ "$app_build" != "$BUILD_NUMBER" ]]; then
            verify_error="App 构建号为 $app_build，应为 $BUILD_NUMBER"
        elif [[ "$app_feed" != *"appcast-$arch.xml" ]]; then
            verify_error="App 更新源为 $app_feed，应指向 appcast-$arch.xml"
        elif ! codesign --verify --deep --strict "$app_path" 2>/dev/null; then
            verify_error="App 签名校验失败"
        elif ! spctl -a -t exec "$app_path" >/dev/null 2>&1; then
            # DMG 本身不做代码签名（公证票据已 staple 在 DMG 上），Gatekeeper 校验针对其中的 App
            verify_error="App 未通过 Gatekeeper 校验"
        fi
    fi
    hdiutil detach "$mount_point" -quiet || true
    rmdir "$mount_point" 2>/dev/null || true
    [[ -z "$verify_error" ]] || fail "$arch: $verify_error"
    echo "$arch: $(basename "$dmg_path") 校验通过"
done

# ---------- 草稿 Release ----------
step "创建草稿 Release 并上传 DMG"
"$SCRIPT_DIR/publish_github_release.sh" \
    --repo "$REPO" \
    --tag "$TAG" \
    --notes-file "$NOTES_FILE" \
    --draft \
    --dmg "${DMG_PATHS[0]}" \
    --dmg "${DMG_PATHS[1]}"

# ---------- appcast ----------
step "生成分架构 appcast"
for index in "${!ARCHS[@]}"; do
    "$SCRIPT_DIR/generate_appcast.sh" \
        --arch "${ARCHS[$index]}" \
        --archive "${DMG_PATHS[$index]}" \
        --repo "$REPO" \
        --notes-file "$NOTES_FILE"
done

step "同步旧版通用 appcast.xml（1.1.0 及更早版本仍从这里检查更新）"
/usr/bin/python3 - "$ROOT_DIR/appcast.xml" "$ROOT_DIR/appcast-arm64.xml" "$ROOT_DIR/appcast-x86_64.xml" "$BUILD_NUMBER" <<'PY'
import copy
import sys
import xml.etree.ElementTree as ET

legacy_path, arm_path, intel_path, build_number = sys.argv[1:5]
sparkle_ns = "http://www.andymatuschak.org/xml-namespaces/sparkle"
ET.register_namespace("sparkle", sparkle_ns)
ET.register_namespace("dc", "http://purl.org/dc/elements/1.1/")

def version_of(item):
    node = item.find(f"{{{sparkle_ns}}}version")
    return (node.text or "").strip() if node is not None else ""

def item_for_build(path):
    for item in ET.parse(path).getroot().find("channel").findall("item"):
        if version_of(item) == build_number:
            return item
    raise SystemExit(f"{path} 中没有构建号 {build_number} 的条目")

legacy_tree = ET.parse(legacy_path)
channel = legacy_tree.getroot().find("channel")
# 去掉同一构建号的旧条目，保证脚本可重复执行
for item in list(channel.findall("item")):
    if version_of(item) == build_number:
        channel.remove(item)

# 版本相同时 Sparkle 取第一个满足硬件要求的条目：arm64 条目带 hardwareRequirements，必须排在 x86_64 前面
first_item_index = next((i for i, child in enumerate(list(channel)) if child.tag == "item"), len(list(channel)))
for offset, path in enumerate((arm_path, intel_path)):
    channel.insert(first_item_index + offset, copy.deepcopy(item_for_build(path)))

ET.indent(legacy_tree, space="    ")
legacy_tree.write(legacy_path, encoding="utf-8", xml_declaration=True)
PY

step "校验 appcast 与 DMG 一致"
SPARKLE_PUBLIC_KEY="$(sed -n 's/^[[:space:]]*INFOPLIST_KEY_SUPublicEDKey:[[:space:]]*//p' project.yml | head -1 | tr -d ' "')"
python3 -c "import cryptography" 2>/dev/null || fail "校验 EdDSA 签名需要 Python cryptography 模块：python3 -m pip install cryptography"
for index in "${!ARCHS[@]}"; do
    arch="${ARCHS[$index]}"
    dmg_path="${DMG_PATHS[$index]}"
    dmg_name="$(basename "$dmg_path")"
    for feed in "appcast-$arch.xml" "appcast.xml"; do
        enclosure="$(enclosure_info "$ROOT_DIR/$feed" "$dmg_name")"
        feed_length="${enclosure%% *}"
        feed_signature="${enclosure#* }"
        [[ "$feed_length" == "$(stat -f '%z' "$dmg_path")" ]] || fail "$feed 中 $dmg_name 的 length 与文件大小不一致"
        verify_ed_signature "$dmg_path" "$feed_signature" || fail "$feed 中 $dmg_name 的 EdDSA 签名校验失败"
    done
    echo "$arch: appcast 校验通过"
done

# 与 Release 中实际上传的资产核对大小
for dmg_path in "${DMG_PATHS[@]}"; do
    dmg_name="$(basename "$dmg_path")"
    remote_size="$(gh release view "$TAG" -R "$REPO" --json assets --jq ".assets[] | select(.name == \"$dmg_name\") | .size")"
    [[ "$remote_size" == "$(stat -f '%z' "$dmg_path")" ]] || fail "Release 中 $dmg_name 的大小（$remote_size）与本地不一致"
done

if [[ "$SHOULD_PUSH" != true ]]; then
    git add appcast.xml appcast-arm64.xml appcast-x86_64.xml
    git commit -m "发布：更新 $VERSION 发布订阅"
    echo
    echo "已在本地提交 appcast，Release 仍为草稿。确认无误后执行："
    echo "  gh release edit $TAG -R $REPO --draft=false --latest && git push origin main"
    exit 0
fi

# ---------- 正式发布 ----------
step "正式发布 Release $TAG"
gh release edit "$TAG" -R "$REPO" --draft=false --latest

step "提交并推送 appcast"
git add appcast.xml appcast-arm64.xml appcast-x86_64.xml
git commit -m "发布：更新 $VERSION 发布订阅"
git push origin main

echo
echo "发布完成: https://github.com/$REPO/releases/tag/$TAG"
