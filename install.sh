#!/usr/bin/env bash
# TouchLyric macOS One-Line Installer
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/rizalzaky23/TouchLyric/main/install.sh | bash

set -e

# Terminal colors
BOLD="\033[1m"
GREEN="\033[0;32m"
CYAN="\033[0;36m"
YELLOW="\033[0;33m"
RED="\033[0;31m"
RESET="\033[0m"

echo -e "${CYAN}${BOLD}"
echo "  ╔═══════════════════════════════════════════════════════╗"
echo "  ║                                                       ║"
echo "  ║             🎵  TouchLyric for macOS  🎵              ║"
echo "  ║        Spotify Synchronized Lyrics on Touch Bar       ║"
echo "  ║                                                       ║"
echo "  ╚═══════════════════════════════════════════════════════╝"
echo -e "${RESET}"

# 1. Verify macOS
OS="$(uname -s)"
if [ "$OS" != "Darwin" ]; then
    echo -e "${RED}Error: TouchLyric only supports macOS with Touch Bar.${RESET}"
    exit 1
fi

REPO="rizalzaky23/TouchLyric"
DOWNLOAD_URL="https://github.com/${REPO}/releases/latest/download/TouchLyric.zip"
TMP_DIR=$(mktemp -d /tmp/touchlyric-install.XXXXXX)

cleanup() {
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT

echo -e "${CYAN}==>${RESET} Downloading latest TouchLyric release..."
if ! curl -fSL "$DOWNLOAD_URL" -o "$TMP_DIR/TouchLyric.zip" --progress-bar; then
    echo -e "${YELLOW}Warning: Could not fetch from latest release URL. Checking fallback...${RESET}"
    FALLBACK_URL="https://github.com/${REPO}/releases/download/v1.0.0/TouchLyric.zip"
    curl -fSL "$FALLBACK_URL" -o "$TMP_DIR/TouchLyric.zip" --progress-bar || {
        echo -e "${RED}Error: Failed to download TouchLyric. Please check your internet connection or visit https://github.com/${REPO}/releases${RESET}"
        exit 1
    }
fi

echo -e "${CYAN}==>${RESET} Extracting TouchLyric..."
unzip -q -o "$TMP_DIR/TouchLyric.zip" -d "$TMP_DIR"

if [ ! -d "$TMP_DIR/TouchLyric.app" ]; then
    echo -e "${RED}Error: Extracted archive does not contain TouchLyric.app${RESET}"
    exit 1
fi

echo -e "${CYAN}==>${RESET} Installing to /Applications..."
pkill -x "TouchLyric" 2>/dev/null || true
sleep 0.5
rm -rf "/Applications/TouchLyric.app"
cp -R "$TMP_DIR/TouchLyric.app" "/Applications/"

echo -e "${CYAN}==>${RESET} Removing Gatekeeper quarantine flags..."
xattr -cr "/Applications/TouchLyric.app" 2>/dev/null || true

echo ""
echo -e "${GREEN}${BOLD}✔ TouchLyric successfully installed in /Applications!${RESET}"
echo ""
echo -e "${CYAN}==>${RESET} Launching TouchLyric..."
open -a "/Applications/TouchLyric.app"

echo ""
echo -e "${BOLD}Enjoy! If prompted by macOS, please allow:${RESET}"
echo -e "  1. Automation permission for ${BOLD}Spotify${RESET} when requested."
echo -e "  2. You can tap the 🎵 icon in your Touch Bar Control Strip to toggle lyrics."
echo ""
