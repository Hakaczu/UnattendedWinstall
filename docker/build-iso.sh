#!/usr/bin/env bash
# build-iso.sh – builds a custom Windows ISO with autounattend.xml injected.
#
# Environment variables:
#   WINDOWS_ISO_URL  Direct URL to download the Windows ISO (mutually exclusive
#                    with mounting an ISO at /input/windows.iso)
#   OUTPUT_NAME      Output ISO filename without extension (default: Windows-Unattended)
#   SMB_HOST         Hostname/IP of the SMB server (optional; skips upload if unset)
#   SMB_SHARE        SMB share name
#   SMB_USER         SMB username
#   SMB_PASSWORD     SMB password
#   SMB_DIR          Subdirectory inside the share (optional)

set -euo pipefail

OUTPUT_NAME="${OUTPUT_NAME:-Windows-Unattended}"
WORK_DIR="/tmp/iso-build"
OUTPUT_DIR="/output"

mkdir -p "$WORK_DIR" "$OUTPUT_DIR"
cd "$WORK_DIR"

# ── 1. Obtain the original Windows ISO ────────────────────────────────────────
if [ -f /input/windows.iso ]; then
    echo "[1/4] Using local ISO from /input/windows.iso"
    ORIG_ISO="/input/windows.iso"
elif [ -n "${WINDOWS_ISO_URL:-}" ]; then
    echo "[1/4] Downloading Windows ISO..."
    curl -fSL --retry 3 --retry-delay 5 -o original.iso "$WINDOWS_ISO_URL"
    echo "      Download complete: $(du -h original.iso | cut -f1)"
    ORIG_ISO="$WORK_DIR/original.iso"
else
    echo "ERROR: Provide a Windows ISO via WINDOWS_ISO_URL or mount it at /input/windows.iso."
    exit 1
fi

# ── 2. Extract ISO contents ────────────────────────────────────────────────────
echo "[2/4] Extracting ISO contents..."
rm -rf iso_contents
mkdir -p iso_contents
xorriso -osirrox on -indev "$ORIG_ISO" -extract / iso_contents/ 2>/dev/null
echo "      Extraction complete."

# ── 3. Inject autounattend.xml ─────────────────────────────────────────────────
echo "[3/4] Injecting autounattend.xml..."
cp /repo/autounattend.xml iso_contents/autounattend.xml
echo "      autounattend.xml placed at ISO root."

# ── 4. Rebuild bootable ISO ────────────────────────────────────────────────────
echo "[4/4] Building custom ISO..."
OUTPUT_ISO="$OUTPUT_DIR/$OUTPUT_NAME.iso"

# Replay El Torito boot parameters from the original so the image boots the
# same way (BIOS + UEFI). Word-splitting of BOOT_ARGS is intentional.
BOOT_ARGS=$(xorriso -indev "$ORIG_ISO" -report_el_torito as_mkisofs 2>/dev/null | tail -n +2)

# shellcheck disable=SC2086
xorriso -as mkisofs \
    -iso-level 3 \
    -full-iso9660-filenames \
    -udf \
    $BOOT_ARGS \
    -o "$OUTPUT_ISO" \
    iso_contents/ 2>/dev/null

echo "      ISO written to $OUTPUT_ISO ($(du -h "$OUTPUT_ISO" | cut -f1))"

# ── Optional: upload to SMB network share ─────────────────────────────────────
if [ -z "${SMB_HOST:-}" ]; then
    echo "SMB_HOST not set – skipping network share upload."
    exit 0
fi

echo "Uploading to SMB share //$SMB_HOST/$SMB_SHARE ..."

# Write SMB credentials to a temporary file (readable only by this process)
# so the password never appears in environment variables or process listings.
CREDS_FILE=$(mktemp)
chmod 600 "$CREDS_FILE"
cat > "$CREDS_FILE" <<EOF
username=${SMB_USER:-}
password=${SMB_PASSWORD:-}
EOF
trap 'rm -f "$CREDS_FILE"' EXIT

cd "$OUTPUT_DIR"

if [ -n "${SMB_DIR:-}" ]; then
    # Create the target directory; ignore error if it already exists.
    smbclient "//$SMB_HOST/$SMB_SHARE" -A "$CREDS_FILE" \
        -c "mkdir \"$SMB_DIR\"" || true
    smbclient "//$SMB_HOST/$SMB_SHARE" -A "$CREDS_FILE" \
        -c "put \"$OUTPUT_NAME.iso\" \"$SMB_DIR/$OUTPUT_NAME.iso\""
else
    smbclient "//$SMB_HOST/$SMB_SHARE" -A "$CREDS_FILE" \
        -c "put \"$OUTPUT_NAME.iso\" \"$OUTPUT_NAME.iso\""
fi

echo "Upload complete."
