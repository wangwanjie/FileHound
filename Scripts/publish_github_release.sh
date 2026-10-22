#!/usr/bin/env bash
#
# 将版本化 DMG 上传到 GitHub Releases。
# 该脚本只负责发布 Release，不自动生成 appcast。
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DEFAULT_DMG_DIR="$ROOT_DIR/build/dmg"
PBXPROJ="$ROOT_DIR/FileHound.xcodeproj/project.pbxproj"

DMG_PATHS=()
REPO=""
TAG=""
TITLE=""
NOTES=""
NOTES_FILE=""
GENERATE_NOTES=false
DRAFT=false
PRERELEASE=false
TARGET_COMMITISH=""
STABLE_NAMES=true
REQUIRED_ARCHS=(arm64 x86_64)

usage() {
    cat <<'EOF'
用法:
  ./Scripts/publish_github_release.sh [--dmg PATH ...] [--repo OWNER/REPO] [--tag TAG]
                                     [--title TITLE] [--notes TEXT | --notes-file FILE | --generate-notes]
                                     [--draft] [--prerelease]

选项:
  --dmg PATH          指定要上传的 DMG，可重复传入多个架构资产；默认选择 build/dmg/ 下当前版本的 arm64 与 x86_64 两个 DMG
  --repo OWNER/REPO   指定 GitHub 仓库，例如 wangwanjie/FileHound
  --tag TAG           指定 release tag，默认根据版本号推导为 v<version>
  --title TITLE       指定 release 标题，默认 FileHound v<version>
  --target REF        指定 release 对应的提交或分支，默认当前 HEAD
  --notes TEXT        指定 release 说明
  --notes-file FILE   从文件读取 release 说明
  --generate-notes    让 GitHub 自动生成 release notes
  --draft             创建草稿 release
  --prerelease        创建预发布 release
  --no-stable-names   不额外上传固定文件名的副本（FileHound-arm64.dmg / FileHound-x86_64.dmg）
  --allow-single-arch 允许只上传一个架构（默认要求 arm64 和 x86_64 都存在）

说明:
  默认会额外上传固定文件名的 DMG 副本，README 可以用
  https://github.com/<repo>/releases/latest/download/FileHound-<arch>.dmg 作为始终指向最新版的下载链接。
  -h, --help          显示帮助

前置条件:
  1. 已安装 GitHub CLI: gh
  2. 已完成登录: gh auth login
  3. 已存在可上传的版本化 DMG，或显式传入 --dmg

下一步:
  发布完成后，请再分别执行 ./Scripts/generate_appcast.sh --arch arm64 / x86_64 生成并更新对应 feed
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

resolve_path() {
    local input_path="$1"
    local candidate="$input_path"

    if [[ -z "$candidate" ]]; then
        printf '\n'
        return 0
    fi

    if [[ "$candidate" != /* ]]; then
        if [[ -e "$ROOT_DIR/$candidate" ]]; then
            candidate="$ROOT_DIR/$candidate"
        fi
    fi

    [[ -e "$candidate" ]] || fail "未找到文件: $input_path"
    (
        cd "$(dirname "$candidate")"
        printf '%s/%s\n' "$(pwd)" "$(basename "$candidate")"
    )
}

extract_github_repo_from_url() {
    local remote_url="$1"

    if [[ "$remote_url" =~ ^https://github\.com/([^/]+)/([^/]+)(\.git)?/?$ ]]; then
        printf '%s/%s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]%.git}"
        return 0
    fi

    if [[ "$remote_url" =~ ^git@github\.com:([^/]+)/([^/]+)(\.git)?$ ]]; then
        printf '%s/%s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]%.git}"
        return 0
    fi

    if [[ "$remote_url" =~ ^ssh://git@github\.com/([^/]+)/([^/]+)(\.git)?$ ]]; then
        printf '%s/%s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]%.git}"
        return 0
    fi

    return 1
}

detect_repo() {
    local remote_name
    local remote_url
    local repo_name

    while IFS=$'\t' read -r remote_name remote_url; do
        if repo_name="$(extract_github_repo_from_url "$remote_url" 2>/dev/null)"; then
            printf '%s\n' "$repo_name"
            return 0
        fi
    done < <(git remote -v | awk '$3=="(push)" {print $1 "\t" $2}' | awk '!seen[$1]++')

    return 1
}

read_build_number() {
    sed -n 's/.*CURRENT_PROJECT_VERSION = \([^;]*\);/\1/p' "$PBXPROJ" | head -1 | tr -d ' '
}

infer_arch_from_dmg() {
    local dmg_name
    dmg_name="$(basename "$1")"

    if [[ "$dmg_name" =~ _(arm64|x86_64)\.dmg$ ]]; then
        printf '%s\n' "${BASH_REMATCH[1]}"
        return 0
    fi

    return 1
}

# 默认上传当前工程版本对应的全部架构 DMG，避免只传了最新生成的一个架构
find_current_version_dmgs() {
    local version
    local build_number
    local arch
    local candidate

    version="$(read_marketing_version)"
    build_number="$(read_build_number)"
    for arch in "${REQUIRED_ARCHS[@]}"; do
        candidate="$DEFAULT_DMG_DIR/FileHound_v${version}_${build_number}_${arch}.dmg"
        if [[ -f "$candidate" ]]; then
            printf '%s\n' "$candidate"
        fi
    done
}

find_latest_dmg() {
    local latest_path=""
    local latest_mtime=0
    local file_path
    local file_mtime

    shopt -s nullglob
    for file_path in "$DEFAULT_DMG_DIR"/FileHound_v*.dmg; do
        [[ -f "$file_path" ]] || continue
        file_mtime="$(stat -f '%m' "$file_path")"
        if [[ -z "$latest_path" || "$file_mtime" -gt "$latest_mtime" ]]; then
            latest_path="$file_path"
            latest_mtime="$file_mtime"
        fi
    done
    shopt -u nullglob

    printf '%s\n' "$latest_path"
}

infer_version_from_dmg() {
    local dmg_name
    dmg_name="$(basename "$1")"

    if [[ "$dmg_name" =~ ^FileHound_v([^_]+)(_.+)?\.dmg$ ]]; then
        printf '%s\n' "${BASH_REMATCH[1]}"
        return 0
    fi

    return 1
}

read_marketing_version() {
    sed -n 's/.*MARKETING_VERSION = \([^;]*\);/\1/p' "$PBXPROJ" | head -1 | tr -d ' '
}

# mode=create 时没有说明会回落到默认文案；mode=edit 时只在显式传入说明时才覆盖，避免冲掉手写的 release notes
build_notes_args() {
    local mode="$1"
    NOTES_ARGS=()
    if [[ "$GENERATE_NOTES" == true ]]; then
        if [[ "$mode" == edit ]]; then
            fail "Release $TAG 已存在，gh release edit 不支持 --generate-notes，请改用 --notes / --notes-file 或不传说明"
        fi
        NOTES_ARGS+=(--generate-notes)
        return
    fi

    if [[ -n "$NOTES_FILE" ]]; then
        NOTES_ARGS+=(--notes-file "$NOTES_FILE")
        return
    fi

    if [[ -n "$NOTES" ]]; then
        NOTES_ARGS+=(--notes "$NOTES")
        return
    fi

    if [[ "$mode" == create ]]; then
        NOTES_ARGS+=(--notes "Release $TAG")
    fi
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dmg)
            [[ -n "${2:-}" && "${2:-}" != --* ]] || fail "--dmg 需要指定文件路径"
            DMG_PATHS+=("$2")
            shift 2
            ;;
        --repo)
            [[ -n "${2:-}" && "${2:-}" != --* ]] || fail "--repo 需要指定 OWNER/REPO"
            REPO="$2"
            shift 2
            ;;
        --tag)
            [[ -n "${2:-}" && "${2:-}" != --* ]] || fail "--tag 需要指定值"
            TAG="$2"
            shift 2
            ;;
        --title)
            [[ -n "${2:-}" && "${2:-}" != --* ]] || fail "--title 需要指定值"
            TITLE="$2"
            shift 2
            ;;
        --target)
            [[ -n "${2:-}" && "${2:-}" != --* ]] || fail "--target 需要指定提交或分支"
            TARGET_COMMITISH="$2"
            shift 2
            ;;
        --notes)
            [[ -n "${2:-}" && "${2:-}" != --* ]] || fail "--notes 需要指定文本"
            NOTES="$2"
            shift 2
            ;;
        --notes-file)
            [[ -n "${2:-}" && "${2:-}" != --* ]] || fail "--notes-file 需要指定文件"
            NOTES_FILE="$2"
            shift 2
            ;;
        --generate-notes)
            GENERATE_NOTES=true
            shift
            ;;
        --draft)
            DRAFT=true
            shift
            ;;
        --prerelease)
            PRERELEASE=true
            shift
            ;;
        --no-stable-names)
            STABLE_NAMES=false
            shift
            ;;
        --allow-single-arch)
            REQUIRED_ARCHS=()
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

if [[ -n "$NOTES" && -n "$NOTES_FILE" ]]; then
    fail "--notes 和 --notes-file 只能二选一"
fi

if [[ "$GENERATE_NOTES" == true && ( -n "$NOTES" || -n "$NOTES_FILE" ) ]]; then
    fail "--generate-notes 不能与 --notes / --notes-file 同时使用"
fi

require_command gh
require_command git
require_command sed
require_command stat

gh auth status >/dev/null 2>&1 || fail "GitHub CLI 未登录，请先执行 gh auth login"

if [[ -z "$TARGET_COMMITISH" ]]; then
    TARGET_COMMITISH="$(git rev-parse HEAD)"
fi

if [[ ${#DMG_PATHS[@]} -gt 0 ]]; then
    for i in "${!DMG_PATHS[@]}"; do
        DMG_PATHS[$i]="$(resolve_path "${DMG_PATHS[$i]}")"
    done
elif [[ ${#REQUIRED_ARCHS[@]} -gt 0 ]]; then
    while IFS= read -r dmg_path; do
        DMG_PATHS+=("$dmg_path")
    done < <(find_current_version_dmgs)
    [[ ${#DMG_PATHS[@]} -gt 0 ]] || fail "未找到当前版本的 DMG，请先执行 ./Scripts/build_dmg.sh --arch arm64 / x86_64"
else
    latest_dmg="$(find_latest_dmg)"
    [[ -n "$latest_dmg" ]] || fail "未找到可上传的 DMG，请先执行 ./Scripts/build_dmg.sh"
    DMG_PATHS+=("$latest_dmg")
fi

# 校验每个必需架构恰好有一个 DMG
if [[ ${#REQUIRED_ARCHS[@]} -gt 0 ]]; then
    for required_arch in "${REQUIRED_ARCHS[@]}"; do
        arch_count=0
        for dmg_path in "${DMG_PATHS[@]}"; do
            if [[ "$(infer_arch_from_dmg "$dmg_path" || true)" == "$required_arch" ]]; then
                arch_count=$((arch_count + 1))
            fi
        done
        [[ "$arch_count" -eq 1 ]] || fail "需要恰好一个 $required_arch 架构的 DMG，实际为 $arch_count 个（如确实只发布单一架构请加 --allow-single-arch）"
    done
fi

for dmg_path in "${DMG_PATHS[@]}"; do
    [[ -f "$dmg_path" ]] || fail "未找到文件: $dmg_path"
done

if [[ -n "$NOTES_FILE" ]]; then
    NOTES_FILE="$(resolve_path "$NOTES_FILE")"
fi

if [[ -z "$REPO" ]]; then
    REPO="$(detect_repo)" || fail "无法从 git remote 推断 GitHub 仓库，请使用 --repo OWNER/REPO"
fi

[[ "$REPO" =~ ^[^/]+/[^/]+$ ]] || fail "--repo 必须是 OWNER/REPO 格式"

VERSION="$(infer_version_from_dmg "${DMG_PATHS[0]}" || true)"
if [[ -z "$VERSION" ]]; then
    VERSION="$(read_marketing_version)"
fi
[[ -n "$VERSION" ]] || fail "无法从 DMG 名称或工程配置推断版本号"

for dmg_path in "${DMG_PATHS[@]}"; do
    dmg_version="$(infer_version_from_dmg "$dmg_path" || true)"
    if [[ -n "$dmg_version" && "$dmg_version" != "$VERSION" ]]; then
        fail "所有上传资产必须属于同一版本，发现 $dmg_path 的版本为 $dmg_version"
    fi
done

if [[ -z "$TAG" ]]; then
    TAG="v$VERSION"
fi

if [[ -z "$TITLE" ]]; then
    TITLE="FileHound v$VERSION"
fi

# 固定文件名副本：让 releases/latest/download/FileHound-<arch>.dmg 始终指向最新版本
UPLOAD_PATHS=("${DMG_PATHS[@]}")
if [[ "$STABLE_NAMES" == true ]]; then
    STABLE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/filehound-release.XXXXXX")"
    trap 'rm -rf "$STABLE_DIR"' EXIT
    for dmg_path in "${DMG_PATHS[@]}"; do
        dmg_arch="$(infer_arch_from_dmg "$dmg_path" || true)"
        if [[ -n "$dmg_arch" ]]; then
            cp "$dmg_path" "$STABLE_DIR/FileHound-${dmg_arch}.dmg"
            UPLOAD_PATHS+=("$STABLE_DIR/FileHound-${dmg_arch}.dmg")
        fi
    done
fi

echo "仓库: $REPO"
echo "Tag: $TAG"
echo "标题: $TITLE"
echo "Target: $TARGET_COMMITISH"
for dmg_path in "${UPLOAD_PATHS[@]}"; do
    echo "上传: $dmg_path"
done

if gh release view "$TAG" -R "$REPO" >/dev/null 2>&1; then
    echo "Release 已存在，先更新元信息，再覆盖上传同名 DMG..."
    edit_args=(release edit "$TAG" -R "$REPO" --title "$TITLE")
    build_notes_args edit
    if [[ ${#NOTES_ARGS[@]} -gt 0 ]]; then
        edit_args+=("${NOTES_ARGS[@]}")
    fi
    if [[ "$DRAFT" == true ]]; then
        edit_args+=(--draft)
    fi
    if [[ "$PRERELEASE" == true ]]; then
        edit_args+=(--prerelease)
    fi
    gh "${edit_args[@]}"
    gh release upload "$TAG" "${UPLOAD_PATHS[@]}" -R "$REPO" --clobber
else
    echo "Release 不存在，创建并上传 DMG..."
    create_args=(release create "$TAG")
    create_args+=("${UPLOAD_PATHS[@]}")
    create_args+=(-R "$REPO" --title "$TITLE" --target "$TARGET_COMMITISH")
    build_notes_args create
    create_args+=("${NOTES_ARGS[@]}")
    if [[ "$DRAFT" == true ]]; then
        create_args+=(--draft)
    fi
    if [[ "$PRERELEASE" == true ]]; then
        create_args+=(--prerelease)
    fi
    gh "${create_args[@]}"
fi

echo "发布完成: https://github.com/$REPO/releases/tag/$TAG"
echo "下一步请分别执行:"
echo "  ./Scripts/generate_appcast.sh --arch arm64 --archive <arm64-dmg> --repo \"$REPO\""
echo "  ./Scripts/generate_appcast.sh --arch x86_64 --archive <x86_64-dmg> --repo \"$REPO\""
