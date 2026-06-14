#!/usr/bin/env bash
# Install the OrgOS Activity Ledger viewer into the central store.
# Idempotent: copies server.py + index.html into <store>/viewer/ and writes a
# tiny serve.sh launcher there. Standalone; only needs the SSOT files next to it.
#
# Store dir: $ORGOS_ACTIVITY_DIR, else ~/.orgos/activity
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC_DIR="$SCRIPT_DIR/viewer"

if [ -n "${ORGOS_ACTIVITY_DIR:-}" ]; then
  STORE_DIR="$ORGOS_ACTIVITY_DIR"
else
  STORE_DIR="$HOME/.orgos/activity"
fi
DEST_DIR="$STORE_DIR/viewer"

if [ ! -f "$SRC_DIR/server.py" ] || [ ! -f "$SRC_DIR/index.html" ]; then
  echo "error: source files not found in $SRC_DIR" >&2
  echo "       (expected server.py and index.html)" >&2
  exit 1
fi

mkdir -p "$DEST_DIR"
cp "$SRC_DIR/server.py" "$DEST_DIR/server.py"
cp "$SRC_DIR/index.html" "$DEST_DIR/index.html"
chmod +x "$DEST_DIR/server.py"

# Tiny standalone launcher next to the copied server.
cat > "$DEST_DIR/serve.sh" <<'LAUNCHER'
#!/usr/bin/env bash
# OrgOS Activity Viewer — standalone launcher.
set -eu
DIR="$(cd "$(dirname "$0")" && pwd)"
exec python3 "$DIR/server.py" "$@"
LAUNCHER
chmod +x "$DEST_DIR/serve.sh"

echo "Installed OrgOS Activity Viewer to:"
echo "  $DEST_DIR"
echo ""
echo "Launch it with either:"
echo "  python3 $DEST_DIR/server.py"
echo "  bash $DEST_DIR/serve.sh"
echo ""
echo "Then open http://127.0.0.1:7777/ (opens automatically unless --no-browser)."
