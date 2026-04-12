#!/usr/bin/env bash
#
# 根据本地归档的 DMG 生成 Sparkle appcast.xml，
# 并将 enclosure URL 改写为 GitHub Releases 资产地址。
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DEFAULT_ARCHIVES_DIR="$ROOT_DIR/build/appcast-archives"
DEFAULT_OUTPUT_PATH="$ROOT_DIR/appcast.xml"
DEFAULT_ACCOUNT="cn.vanjay.FileHound.sparkle"

ARCHIVE_PATH=""
ARCHIVES_DIR="$DEFAULT_ARCHIVES_DIR"
OUTPUT_PATH="$DEFAULT_OUTPUT_PATH"
REPO=""
ACCOUNT="$DEFAULT_ACCOUNT"
NOTES=""
NOTES_FILE=""

usage() {
    cat <<'EOF'
用法:
  ./Scripts/generate_appcast.sh [--archive PATH] [--archives-dir DIR] [--output PATH]
                                [--repo OWNER/REPO] [--account ACCOUNT]
                                [--notes TEXT | --notes-file FILE]

选项:
  --archive PATH       将当前版本 DMG 复制到本地归档目录后再生成 appcast
  --archives-dir DIR   DMG 归档目录，默认 build/appcast-archives
  --output PATH        appcast.xml 输出路径，默认仓库根目录
  --repo OWNER/REPO    GitHub 仓库，例如 wangwanjie/FileHound
  --account ACCOUNT    Sparkle EdDSA Keychain account，默认 cn.vanjay.FileHound.sparkle
  --notes TEXT         为当前 archive 写入同名 .md 发布说明
  --notes-file FILE    为当前 archive 复制同名说明文件（支持 .md/.txt/.html）
  -h, --help           显示帮助

前置条件:
  1. 已构建 Sparkle 包依赖
  2. 已在本机生成 Sparkle 私钥:
     <Sparkle bin>/generate_keys --account cn.vanjay.FileHound.sparkle
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

    candidate="${candidate/#\~/$HOME}"

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

    if [[ "$remote_url" =~ ^https://github\.com/([^/]+)/([^/]+?)(\.git)?/?$ ]]; then
        printf '%s/%s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
        return 0
    fi

    if [[ "$remote_url" =~ ^git@github\.com:([^/]+)/([^/]+?)(\.git)?$ ]]; then
        printf '%s/%s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
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

find_sparkle_bin_dir() {
    local candidate

    if [[ -n "${SPARKLE_BIN_DIR:-}" && -x "${SPARKLE_BIN_DIR}/generate_appcast" ]]; then
        printf '%s\n' "$SPARKLE_BIN_DIR"
        return 0
    fi

    while IFS= read -r candidate; do
        if [[ -x "$candidate/generate_appcast" && -x "$candidate/generate_keys" ]]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done < <(find "$ROOT_DIR/build/DerivedData" "$HOME/Library/Developer/Xcode/DerivedData" \
        -path '*/SourcePackages/artifacts/sparkle/Sparkle/bin' -type d 2>/dev/null | sort -r)

    return 1
}

copy_release_notes() {
    local archive_dest="$1"
    local base_path="${archive_dest%.*}"

    if [[ -n "$NOTES_FILE" ]]; then
        local ext="${NOTES_FILE##*.}"
        cp "$NOTES_FILE" "${base_path}.${ext}"
    elif [[ -n "$NOTES" ]]; then
        printf '%s\n' "$NOTES" > "${base_path}.md"
    fi
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --archive)
            [[ -n "${2:-}" && "${2:-}" != --* ]] || fail "--archive 需要指定 DMG 路径"
            ARCHIVE_PATH="$2"
            shift 2
            ;;
        --archives-dir)
            [[ -n "${2:-}" && "${2:-}" != --* ]] || fail "--archives-dir 需要指定目录"
            ARCHIVES_DIR="$2"
            shift 2
            ;;
        --output)
            [[ -n "${2:-}" && "${2:-}" != --* ]] || fail "--output 需要指定输出路径"
            OUTPUT_PATH="$2"
            shift 2
            ;;
        --repo)
            [[ -n "${2:-}" && "${2:-}" != --* ]] || fail "--repo 需要指定 OWNER/REPO"
            REPO="$2"
            shift 2
            ;;
        --account)
            [[ -n "${2:-}" && "${2:-}" != --* ]] || fail "--account 需要指定 Sparkle account"
            ACCOUNT="$2"
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

require_command git
require_command python3
require_command /usr/libexec/PlistBuddy

ARCHIVES_DIR="${ARCHIVES_DIR/#\~/$HOME}"
OUTPUT_PATH="${OUTPUT_PATH/#\~/$HOME}"

if [[ -n "$ARCHIVE_PATH" ]]; then
    ARCHIVE_PATH="$(resolve_path "$ARCHIVE_PATH")"
fi

if [[ -n "$NOTES_FILE" ]]; then
    NOTES_FILE="$(resolve_path "$NOTES_FILE")"
fi

if [[ -z "$REPO" ]]; then
    REPO="$(detect_repo)" || fail "无法从 git remote 推断 GitHub 仓库，请使用 --repo OWNER/REPO"
fi

[[ "$REPO" =~ ^[^/]+/[^/]+$ ]] || fail "--repo 必须是 OWNER/REPO 格式"

SPARKLE_BIN_DIR="$(find_sparkle_bin_dir)" || fail "未找到 Sparkle 工具，请先构建一次工程或设置 SPARKLE_BIN_DIR"

if ! "$SPARKLE_BIN_DIR/generate_keys" --account "$ACCOUNT" -p >/dev/null 2>&1; then
    fail "未找到 Sparkle 私钥，请先执行: $SPARKLE_BIN_DIR/generate_keys --account $ACCOUNT"
fi

mkdir -p "$ARCHIVES_DIR"

if [[ -n "$ARCHIVE_PATH" ]]; then
    archive_dest="$ARCHIVES_DIR/$(basename "$ARCHIVE_PATH")"
    cp "$ARCHIVE_PATH" "$archive_dest"
    copy_release_notes "$archive_dest"
fi

shopt -s nullglob
archives=( "$ARCHIVES_DIR"/*.dmg )
shopt -u nullglob

if [[ ${#archives[@]} -eq 0 ]]; then
    fail "$ARCHIVES_DIR 中没有可用于生成 appcast 的 DMG"
fi

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/filehound-appcast.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

cp "$ARCHIVES_DIR"/*.dmg "$TMP_DIR/"
for notes_path in "$ARCHIVES_DIR"/*.md "$ARCHIVES_DIR"/*.txt "$ARCHIVES_DIR"/*.html; do
    [[ -e "$notes_path" ]] || continue
    cp "$notes_path" "$TMP_DIR/"
done

TMP_APPCAST="$TMP_DIR/appcast.xml"
"$SPARKLE_BIN_DIR/generate_appcast" \
    --account "$ACCOUNT" \
    --link "https://github.com/$REPO" \
    -o "$TMP_APPCAST" \
    "$TMP_DIR"

/usr/bin/python3 - "$TMP_APPCAST" "$OUTPUT_PATH" "$REPO" "$TMP_DIR" <<'PY'
import html
import pathlib
import re
import sys
import urllib.parse
import xml.etree.ElementTree as ET

input_path, output_path, repo, archives_dir = sys.argv[1:5]
sparkle_ns = "http://www.andymatuschak.org/xml-namespaces/sparkle"
dc_ns = "http://purl.org/dc/elements/1.1/"
ET.register_namespace("sparkle", sparkle_ns)
ET.register_namespace("dc", dc_ns)

tree = ET.parse(input_path)
root = tree.getroot()
channel = root.find("channel")
if channel is None:
    raise SystemExit("appcast 中缺少 channel 节点")

def find_or_create(parent, tag):
    node = parent.find(tag)
    if node is None:
        node = ET.SubElement(parent, tag)
    return node

def replace_inline_markup(text):
    escaped = html.escape(text, quote=False)

    def replace_markdown_link(match):
        label = match.group(1)
        url = html.escape(match.group(2), quote=True)
        return f'<a href="{url}">{label}</a>'

    escaped = re.sub(r"\[([^\]]+)\]\((https?://[^)]+)\)", replace_markdown_link, escaped)
    escaped = re.sub(r"(?<!\*)\*\*([^*]+)\*\*", r"<strong>\1</strong>", escaped)
    escaped = re.sub(r"(?<!\*)\*([^*]+)\*", r"<em>\1</em>", escaped)
    url_pattern = re.compile(r"(?<![\"'>])(https?://[^\s<]+)")
    escaped = url_pattern.sub(lambda match: f'<a href="{html.escape(match.group(1), quote=True)}">{match.group(1)}</a>', escaped)
    return escaped

def markdown_to_html(markdown_text):
    lines = markdown_text.replace("\r\n", "\n").replace("\r", "\n").split("\n")
    blocks = []
    paragraph_lines = []
    list_items = []
    in_code_block = False
    code_lines = []

    def flush_paragraph():
        nonlocal paragraph_lines
        if not paragraph_lines:
            return
        content = "<br/>".join(replace_inline_markup(line.strip()) for line in paragraph_lines if line.strip())
        if content:
            blocks.append(f"<p>{content}</p>")
        paragraph_lines = []

    def flush_list():
        nonlocal list_items
        if not list_items:
            return
        items_html = "".join(f"<li>{replace_inline_markup(item)}</li>" for item in list_items)
        blocks.append(f"<ul>{items_html}</ul>")
        list_items = []

    def flush_code_block():
        nonlocal code_lines
        if not code_lines:
            return
        blocks.append(f"<pre><code>{html.escape(chr(10).join(code_lines))}</code></pre>")
        code_lines = []

    for raw_line in lines:
        line = raw_line.rstrip()
        stripped = line.strip()

        if stripped.startswith("```"):
            flush_paragraph()
            flush_list()
            if in_code_block:
                flush_code_block()
            in_code_block = not in_code_block
            continue

        if in_code_block:
            code_lines.append(line)
            continue

        if not stripped:
            flush_paragraph()
            flush_list()
            continue

        heading_match = re.match(r"^(#{1,6})\s+(.*)$", stripped)
        if heading_match:
            flush_paragraph()
            flush_list()
            level = len(heading_match.group(1))
            blocks.append(f"<h{level}>{replace_inline_markup(heading_match.group(2).strip())}</h{level}>")
            continue

        if re.fullmatch(r"[-*_]{3,}", stripped):
            flush_paragraph()
            flush_list()
            blocks.append("<hr/>")
            continue

        list_match = re.match(r"^[-*]\s+(.*)$", stripped)
        if list_match:
            flush_paragraph()
            list_items.append(list_match.group(1).strip())
            continue

        flush_list()
        paragraph_lines.append(line)

    flush_paragraph()
    flush_list()
    if in_code_block:
        flush_code_block()

    return "\n".join(blocks).strip()

def plain_text_to_html(text):
    escaped = html.escape(text.strip(), quote=False)
    if not escaped:
        return ""
    escaped = escaped.replace("\r\n", "\n").replace("\r", "\n")
    return f"<div style=\"white-space: pre-wrap;\">{escaped}</div>"

def load_release_notes_html(filename):
    base_name = pathlib.Path(filename).stem
    base_path = pathlib.Path(archives_dir) / base_name

    html_path = pathlib.Path(f"{base_path}.html")
    if html_path.exists():
        return html_path.read_text(encoding="utf-8").strip()

    markdown_path = pathlib.Path(f"{base_path}.md")
    if markdown_path.exists():
        return markdown_to_html(markdown_path.read_text(encoding="utf-8"))

    text_path = pathlib.Path(f"{base_path}.txt")
    if text_path.exists():
        return plain_text_to_html(text_path.read_text(encoding="utf-8"))

    return ""

title_node = find_or_create(channel, "title")
if not (title_node.text or "").strip():
    title_node.text = "FileHound Updates"

link_node = find_or_create(channel, "link")
link_node.text = f"https://github.com/{repo}"

description_node = find_or_create(channel, "description")
if not (description_node.text or "").strip():
    description_node.text = "FileHound release feed."

language_node = find_or_create(channel, "language")
if not (language_node.text or "").strip():
    language_node.text = "zh-CN"

for item in channel.findall("item"):
    enclosure = item.find("enclosure")
    if enclosure is None:
        continue

    raw_url = enclosure.attrib.get("url", "")
    parsed_path = urllib.parse.urlparse(raw_url).path
    filename = pathlib.PurePosixPath(parsed_path).name or pathlib.Path(raw_url).name
    if not filename:
        continue

    match = re.match(r"FileHound_v([^_]+)(?:_(.+))?\.dmg$", filename)
    version = match.group(1) if match else None

    if not version:
        short_version = item.find(f"{{{sparkle_ns}}}shortVersionString")
        version = (short_version.text or "").strip() if short_version is not None else ""

    if not version:
        raise SystemExit(f"无法从 {filename} 推断版本号")

    version = version.lstrip("vV")
    tag = f"v{version}"
    quoted_tag = urllib.parse.quote(tag, safe="")
    quoted_file = urllib.parse.quote(filename, safe="")
    release_url = f"https://github.com/{repo}/releases/tag/{quoted_tag}"
    download_url = f"https://github.com/{repo}/releases/download/{quoted_tag}/{quoted_file}"

    enclosure.set("url", download_url)

    item_link = find_or_create(item, "link")
    item_link.text = release_url

    description = find_or_create(item, "description")
    release_notes_html = load_release_notes_html(filename)
    if release_notes_html:
        description.text = release_notes_html

    for node_name in ("releaseNotesLink", "fullReleaseNotesLink"):
        node = item.find(f"{{{sparkle_ns}}}{node_name}")
        if node is not None:
            item.remove(node)

ET.indent(tree, space="    ")
tree.write(output_path, encoding="utf-8", xml_declaration=True)
PY

echo "已生成 appcast: $OUTPUT_PATH"
echo "归档目录: $ARCHIVES_DIR"
