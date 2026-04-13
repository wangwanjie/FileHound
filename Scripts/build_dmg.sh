#!/usr/bin/env bash
#
# 打包 FileHound 为正式分发 DMG：
# - 从 FileHound.xcworkspace 归档 Release
# - 生成带版本号、构建号和架构后缀的 DMG
# - 默认执行 notarize + staple
#
# 用法:
#   ./Scripts/build_dmg.sh --arch arm64|x86_64 [--keychain-profile PROFILE] [--no-notarize]
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
WORKSPACE="$ROOT_DIR/FileHound.xcworkspace"
PBXPROJ="$ROOT_DIR/FileHound.xcodeproj/project.pbxproj"
SCHEME="FileHound"
CONFIGURATION="Release"
BUILD_DIR="$ROOT_DIR/build"
DMG_OUTPUT_DIR="$BUILD_DIR/dmg"
APP_ENTITLEMENTS="$ROOT_DIR/FileHound/FileHound.entitlements"
KEYCHAIN_PROFILE="vanjay_mac_stapler"
SHOULD_NOTARIZE=true
ARCH=""
DERIVED_DATA=""
ARCHIVE_PATH=""
APP_PATH=""
DMG_PATH=""
SPARKLE_PUBLIC_KEY="EMkumAR7FRbjJ6T5LhBcK7yIcGnJAuAjU5RZFEm12JE="
SPARKLE_FEED_BASE_URL="https://raw.githubusercontent.com/wangwanjie/FileHound/main"

usage() {
    cat <<'EOF'
用法:
  ./Scripts/build_dmg.sh --arch arm64|x86_64 [--keychain-profile PROFILE] [--no-notarize]

说明:
  默认从 FileHound.xcworkspace 按指定架构归档 Release，并走正式发布链路：
  1. 校验签名 / 公证前置条件
  2. 为对应架构写入 Sparkle feed 元数据
  3. 生成带版本号、构建号和架构后缀的 DMG
  4. 默认执行 notarize + staple

选项:
  --arch ARCH                 指定目标架构，必须是 arm64 或 x86_64
  --keychain-profile PROFILE   指定 notarytool keychain profile，默认 vanjay_mac_stapler
  --no-notarize                跳过 notarize + staple，仅用于本地测试
  -h, --help                   显示帮助

输出:
  build/dmg/FileHound_v<MARKETING_VERSION>_<CURRENT_PROJECT_VERSION>_<ARCH>.dmg
EOF
}

fail() {
    echo "错误: $*" >&2
    exit 1
}

require_command() {
    local command_name="$1"
    command -v "$command_name" >/dev/null 2>&1 || fail "未找到命令 $command_name"
}

validate_arch() {
    case "$ARCH" in
        arm64|x86_64)
            ;;
        *)
            fail "--arch 必须是 arm64 或 x86_64"
            ;;
    esac
}

read_project_setting() {
    local key="$1"
    local value

    [[ -f "$PBXPROJ" ]] || fail "未找到工程文件 $PBXPROJ"
    value="$(sed -n "s/.*$key = \\([^;]*\\);/\\1/p" "$PBXPROJ" | head -1 | tr -d ' ')"
    printf '%s\n' "$value"
}

current_signing_authority() {
    local target_path="$1"
    codesign -dv --verbose=4 "$target_path" 2>&1 | sed -n 's/^Authority=\(Developer ID Application:.*\)$/\1/p' | head -1
}

verify_release_signature() {
    local target_path="$1"
    local target_name="$2"
    local sign_info

    sign_info="$(codesign -dv --verbose=4 "$target_path" 2>&1)"

    if ! grep -q "Authority=Developer ID Application" <<<"$sign_info"; then
        echo "$sign_info" >&2
        fail "$target_name 未使用 Developer ID Application 签名。请先为 Release 配置 Developer ID 签名后再打包。"
    fi

    if ! grep -q "Timestamp=" <<<"$sign_info"; then
        echo "$sign_info" >&2
        fail "$target_name 缺少 secure timestamp，无法进入正式公证链路。"
    fi
}

validate_notary_profile() {
    local output

    if ! output="$(xcrun notarytool history --keychain-profile "$KEYCHAIN_PROFILE" 2>&1)"; then
        echo "$output" >&2
        fail "无法使用 notarytool profile \"$KEYCHAIN_PROFILE\"。请先确认凭证已配置，或使用 --keychain-profile 指定可用 profile。"
    fi
}

validate_release_prerequisites() {
    require_command xcodebuild
    require_command codesign
    require_command xcrun
    require_command /usr/libexec/PlistBuddy
    require_command create_pretty_dmg.sh
    require_command security
    require_command file
    require_command sed
    require_command grep

    [[ -d "$WORKSPACE" ]] || fail "未找到 workspace：$WORKSPACE"
    [[ -f "$APP_ENTITLEMENTS" ]] || fail "未找到 entitlements：$APP_ENTITLEMENTS"

    if ! security find-identity -v -p codesigning | grep -q "Developer ID Application"; then
        fail "当前钥匙串中没有可用的 Developer ID Application 证书，无法生成可公证的正式包。"
    fi

    if [[ "$SHOULD_NOTARIZE" == true ]]; then
        validate_notary_profile
    fi
}

upsert_plist_string() {
    local plist_path="$1"
    local key="$2"
    local value="$3"

    if /usr/libexec/PlistBuddy -c "Print :$key" "$plist_path" >/dev/null 2>&1; then
        /usr/libexec/PlistBuddy -c "Set :$key $value" "$plist_path"
    else
        /usr/libexec/PlistBuddy -c "Add :$key string $value" "$plist_path"
    fi
}

ensure_sparkle_bundle_metadata() {
    local plist_path="$APP_PATH/Contents/Info.plist"

    [[ -f "$plist_path" ]] || fail "未找到归档 Info.plist：$plist_path"
    upsert_plist_string "$plist_path" "SUFeedURL" "$SPARKLE_FEED_URL"
    upsert_plist_string "$plist_path" "SUPublicEDKey" "$SPARKLE_PUBLIC_KEY"
}

resign_for_release() {
    local identity="$1"
    local nested_path

    echo "重新签名发布产物并补充 hardened runtime..."

    if [[ -d "$APP_PATH/Contents" ]]; then
        while IFS= read -r -d '' nested_path; do
            if [[ "$nested_path" == "$APP_PATH/Contents/MacOS/FileHound" ]]; then
                continue
            fi

            if file "$nested_path" | grep -q "Mach-O"; then
                /usr/bin/codesign --force --sign "$identity" --timestamp --options runtime "$nested_path"
            fi
        done < <(find "$APP_PATH/Contents" -type f -print0)
    fi

    /usr/bin/codesign --force --deep --sign "$identity" --timestamp --options runtime \
        --entitlements "$APP_ENTITLEMENTS" \
        "$APP_PATH"

    /usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_PATH"
}

create_versioned_dmg() {
    local output
    local raw_path
    local expected_path="$DMG_OUTPUT_DIR/FileHound_v${VERSION}_${BUILD_NUMBER}_${ARCH}.dmg"

    mkdir -p "$DMG_OUTPUT_DIR"
    rm -f "$DMG_OUTPUT_DIR"/FileHound_v*_"$ARCH".dmg

    output="$(create_pretty_dmg.sh \
        --app-path "$APP_PATH" \
        --dmg-name "FileHound" \
        --append-version \
        --append-build \
        --output-dir "$DMG_OUTPUT_DIR" 2>&1)"
    printf '%s\n' "$output"

    DMG_PATH="$(printf '%s\n' "$output" | sed -n 's/^DMG_PATH: //p' | tail -1)"
    if [[ -z "$DMG_PATH" ]]; then
        DMG_PATH="$DMG_OUTPUT_DIR/FileHound_v${VERSION}_${BUILD_NUMBER}.dmg"
    fi

    raw_path="$DMG_PATH"
    [[ -f "$raw_path" ]] || fail "未找到生成后的 DMG：$raw_path"

    if [[ "$raw_path" != "$expected_path" ]]; then
        mv -f "$raw_path" "$expected_path"
    fi

    DMG_PATH="$expected_path"
}

notarize_and_staple() {
    local notary_output
    local notary_id

    echo "提交公证: $DMG_PATH"
    if ! notary_output="$(xcrun notarytool submit "$DMG_PATH" --keychain-profile "$KEYCHAIN_PROFILE" --wait 2>&1)"; then
        echo "$notary_output" >&2
        fail "notarize 提交失败。"
    fi

    printf '%s\n' "$notary_output"

    if ! grep -q "status: Accepted" <<<"$notary_output"; then
        notary_id="$(printf '%s\n' "$notary_output" | sed -n 's/.*id:[[:space:]]*\([^[:space:]]*\).*/\1/p' | head -1)"
        if [[ -n "$notary_id" ]]; then
            echo "可查看失败日志: xcrun notarytool log $notary_id --keychain-profile \"$KEYCHAIN_PROFILE\"" >&2
        fi
        fail "公证未通过。"
    fi

    echo "公证成功，开始 staple..."
    xcrun stapler staple "$DMG_PATH"
    xcrun stapler validate "$DMG_PATH"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --arch)
            [[ -n "${2:-}" && "${2:-}" != --* ]] || fail "--arch 需要指定 arm64 或 x86_64"
            ARCH="$2"
            shift 2
            ;;
        --keychain-profile)
            [[ -n "${2:-}" && "${2:-}" != --* ]] || fail "--keychain-profile 需要指定 profile 名称"
            KEYCHAIN_PROFILE="$2"
            shift 2
            ;;
        --no-notarize)
            SHOULD_NOTARIZE=false
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

validate_arch
DERIVED_DATA="$BUILD_DIR/DerivedData-$ARCH"
ARCHIVE_PATH="$BUILD_DIR/FileHound-$ARCH.xcarchive"
APP_PATH="$ARCHIVE_PATH/Products/Applications/FileHound.app"
SPARKLE_FEED_URL="$SPARKLE_FEED_BASE_URL/appcast-${ARCH}.xml"

validate_release_prerequisites

VERSION="$(read_project_setting "MARKETING_VERSION")"
BUILD_NUMBER="$(read_project_setting "CURRENT_PROJECT_VERSION")"
[[ -n "$VERSION" ]] || fail "无法从工程读取 MARKETING_VERSION"
[[ -n "$BUILD_NUMBER" ]] || fail "无法从工程读取 CURRENT_PROJECT_VERSION"

echo "架构: $ARCH"
echo "版本号: $VERSION"
echo "构建号: $BUILD_NUMBER"
echo "Feed: $SPARKLE_FEED_URL"

rm -rf "$ARCHIVE_PATH" "$DERIVED_DATA"
mkdir -p "$BUILD_DIR"

echo "归档 $SCHEME (Release / $ARCH)..."
xcodebuild \
    -workspace "$WORKSPACE" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -derivedDataPath "$DERIVED_DATA" \
    -archivePath "$ARCHIVE_PATH" \
    -destination "generic/platform=macOS" \
    ARCHS="$ARCH" \
    ONLY_ACTIVE_ARCH=NO \
    INFOPLIST_KEY_SUFeedURL="$SPARKLE_FEED_URL" \
    INFOPLIST_KEY_SUPublicEDKey="$SPARKLE_PUBLIC_KEY" \
    clean archive

[[ -d "$APP_PATH" ]] || fail "未找到归档产物 $APP_PATH"
ensure_sparkle_bundle_metadata

SIGNING_AUTHORITY="$(current_signing_authority "$APP_PATH")"
[[ -n "$SIGNING_AUTHORITY" ]] || fail "归档结果未识别到 Developer ID Application 签名。请先修正 Release 签名设置。"

resign_for_release "$SIGNING_AUTHORITY"
verify_release_signature "$APP_PATH" "FileHound.app"

create_versioned_dmg
echo "DMG 已生成: $DMG_PATH"

if [[ "$SHOULD_NOTARIZE" == true ]]; then
    notarize_and_staple
else
    echo "已跳过 notarize + staple，仅用于本地测试。"
fi

echo "完成。正式产物: $DMG_PATH"
