#!/bin/sh
# Brand the Airbyte web UI inside the airbyte/server jar.
# Airbyte serves its UI from webapp/ inside io.airbyte-airbyte-server-<version>.jar. This unpacks
# that folder, adds the PA ETL files (served at /assets/pa/, the only static folder Airbyte serves besides /fonts), patches index.html and the icons, and
# writes the changes back into the jar. Usage: patch-webapp.sh <jar> <brand-dir>
set -eu
JAR="$1"; BRAND="$2"; WORK=$(mktemp -d)
cd "$WORK"
unzip -q "$JAR" 'webapp/*'
W=webapp

mkdir -p "$W/assets/pa"
for f in logo.svg logo-dark.svg mark.svg mark-animated.svg icon.png apple-icon.png favicon.ico airbyte.css brand.js; do
  cp "$BRAND/$f" "$W/assets/pa/$f"
done

# index.html: title, theme and brand script
sed -i 's|<title>[^<]*</title>|<title>PA ETL \&middot; Data sync</title>|' "$W/index.html"
sed -i 's|</head>|<link rel="stylesheet" href="/assets/pa/airbyte.css"><script defer src="/assets/pa/brand.js"></script></head>|' "$W/index.html"

# icons and the no-JavaScript logo
[ -f "$W/favicon.ico" ] && cp "$BRAND/icon.png" "$W/favicon.ico"
[ -f "$W/apple-touch-icon.png" ] && cp "$BRAND/apple-icon.png" "$W/apple-touch-icon.png"
[ -f "$W/logo.png" ] && cp "$BRAND/icon.png" "$W/logo.png"

zip -qr "$JAR" webapp
echo "pa-etl: branded $(basename "$JAR")"
