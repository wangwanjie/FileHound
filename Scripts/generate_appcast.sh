#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT_DIR/build/Build/Products/Release/FileHound.app/Contents/Info.plist" 2>/dev/null || printf '0.1.0')"
PUB_DATE="$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S %z')"

cat > "$ROOT_DIR/appcast.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>FileHound Updates</title>
    <item>
      <title>FileHound $VERSION</title>
      <pubDate>$PUB_DATE</pubDate>
      <enclosure url="https://example.com/FileHound-$VERSION.dmg" sparkle:version="$VERSION" type="application/octet-stream" />
    </item>
  </channel>
</rss>
EOF

printf 'Appcast generated at %s/appcast.xml\n' "$ROOT_DIR"
