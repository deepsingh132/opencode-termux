#!/data/data/com.termux/files/usr/bin/bash
# termux-upgrade.sh — one-command build + install of native OpenCode on Termux.
#
# Usage (from the repo root or anywhere inside it):
#   ./scripts/termux-upgrade.sh                 # build + install the latest opencode
#   ./scripts/termux-upgrade.sh 1.18.31         # build + install a specific version
#   ./scripts/termux-upgrade.sh --release       # skip the build; install latest .deb from GitHub
#   ./scripts/termux-upgrade.sh --release 1.18.31
#   ./scripts/termux-upgrade.sh --no-install    # build the .deb only
#   ./scripts/termux-upgrade.sh --force         # rebuild even if that version is installed
#   ./scripts/termux-upgrade.sh --pacman        # also build the pacman package
#   ./scripts/termux-upgrade.sh --no-pull       # do not 'git pull' the repo first
#
# Standalone use (no local clone): run this file directly and it will clone
#   OPENCODE_TERMUX_REPO (default: deepsingh132/opencode-termux) to
#   OPENCODE_TERMUX_DIR (default: $HOME/opencode-termux), then build.
#
# What it does (build mode):
#   1. ensure Termux dependencies (python/npm/make/clang/patch/llvm/dpkg/git/curl)
#   2. resolve target version (arg or latest 'opencode-linux-arm64' on npm)
#   3. stage the prebuilt bionic libopentui.so (seccomp shim is built on-device)
#   4. make transplant VER=<v>   (graft + revive + TUI swap + harden + tui_probe)
#   5. make deb-native VER=<v>
#   6. dpkg -i the resulting .deb and verify 'opencode --version'
#
set -euo pipefail

PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
export TMPDIR="${TMPDIR:-$PREFIX/tmp}"

REPO_URL="${OPENCODE_TERMUX_REPO:-https://github.com/deepsingh132/opencode-termux.git}"
BRANCH="${OPENCODE_TERMUX_BRANCH:-native-android}"
REPO_DIR="${OPENCODE_TERMUX_DIR:-$HOME/opencode-termux}"

log() { printf '[termux-upgrade] %s\n' "$*"; }
warn() { printf '[termux-upgrade] WARN: %s\n' "$*" >&2; }
die() { printf '[termux-upgrade] ERROR: %s\n' "$*" >&2; exit 1; }

usage() {
	sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'
}

VERSION=""
MODE="build"
DO_INSTALL=1
FORCE=0
DO_PULL=1
DO_PACMAN=0

while [ $# -gt 0 ]; do
	case "$1" in
	-h | --help)
		usage
		exit 0
		;;
	--release) MODE="release" ;;
	--build) MODE="build" ;;
	--no-install) DO_INSTALL=0 ;;
	--force) FORCE=1 ;;
	--no-pull) DO_PULL=0 ;;
	--pacman) DO_PACMAN=1 ;;
	-*) die "unknown option: $1 (try --help)" ;;
	*)
		[ -z "$VERSION" ] || die "unexpected extra argument: $1"
		VERSION="$1"
		;;
	esac
	shift
done
VERSION="${VERSION#v}"

# --- locate or clone the repo -------------------------------------------------
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")"
find_repo_root() {
	local d="$1"
	while [ "$d" != "/" ]; do
		if [ -f "$d/Makefile" ] && [ -f "$d/tools/transplant/transplant.py" ]; then
			printf '%s' "$d"
			return 0
		fi
		d="$(dirname "$d")"
	done
	return 1
}

if repo_root="$(find_repo_root "$(dirname "$SCRIPT_PATH")")"; then
	REPO_DIR="$repo_root"
else
	log "No local checkout found; using $REPO_DIR"
	if [ ! -d "$REPO_DIR/.git" ]; then
		command -v git >/dev/null 2>&1 || die "git is required to clone the repo"
		log "Cloning $REPO_URL ($BRANCH) ..."
		git clone --branch "$BRANCH" "$REPO_URL" "$REPO_DIR"
	fi
fi
cd "$REPO_DIR"

# --- refresh the pipeline (re-exec if the script itself changed) --------------
if [ "$DO_PULL" = 1 ] && [ -d .git ] && [ "${OC_PULLED:-0}" != 1 ]; then
	before="$(git rev-parse HEAD 2>/dev/null || true)"
	if git pull --ff-only --quiet 2>/dev/null; then
		after="$(git rev-parse HEAD 2>/dev/null || true)"
		if [ "$before" != "$after" ] && [ -f "$SCRIPT_PATH" ]; then
			log "repo updated; re-executing $SCRIPT_PATH"
			OC_PULLED=1 exec bash "$SCRIPT_PATH" "$@"
		fi
	else
		warn "git pull failed; continuing with the local checkout"
	fi
fi

# --- dependencies -------------------------------------------------------------
ensure_deps() {
	local missing=() cmd pkg
	for pair in python3:python npm:npm make:make clang:clang patch:patch \
		llvm-strip:llvm dpkg-deb:dpkg git:git curl:curl; do
		cmd="${pair%%:*}"
		pkg="${pair##*:}"
		if ! command -v "$cmd" >/dev/null 2>&1; then
			missing+=("$pkg")
		fi
	done
	if [ "${#missing[@]}" -gt 0 ]; then
		log "installing missing packages: ${missing[*]}"
		command -v pkg >/dev/null 2>&1 || die "missing ${missing[*]} and 'pkg' not available"
		pkg install -y "${missing[@]}"
	fi
}

# --- resolve version ----------------------------------------------------------
resolve_version() {
	if [ -n "$VERSION" ]; then
		printf '%s' "$VERSION"
		return 0
	fi
	command -v npm >/dev/null 2>&1 || die "npm is required to resolve the latest version (or pass a version)"
	npm view opencode-linux-arm64 version
}

# --- main ---------------------------------------------------------------------
if [ "$MODE" = "build" ]; then
	ensure_deps
fi
command -v dpkg >/dev/null 2>&1 || die "dpkg is required to install the package"

VERSION="$(resolve_version)"
[ -n "$VERSION" ] || die "could not resolve a target version"
log "target opencode version: $VERSION"

CURRENT="$(opencode --version 2>/dev/null || echo none)"
if [ "$CURRENT" = "$VERSION" ] && [ "$FORCE" != 1 ] && [ "$MODE" = "build" ]; then
	log "opencode $VERSION is already installed (use --force to rebuild)."
	exit 0
fi
log "installed: $CURRENT -> target: $VERSION"

DEB=""

if [ "$MODE" = "release" ]; then
	URL="https://github.com/deepsingh132/opencode-termux/releases/download/native-${VERSION}/opencode_${VERSION}_aarch64.deb"
	outdir="$TMPDIR/opencode-termux"
	mkdir -p "$outdir"
	DEB="$outdir/opencode_${VERSION}_aarch64.deb"
	log "downloading release package: $URL"
	curl -fL --retry 3 --retry-delay 2 -o "$DEB" "$URL" ||
		die "release native-${VERSION} not found; try build mode (no --release)"
else
	# Stage the version-independent prebuilts the pipeline expects.
	mkdir -p artifacts/transplant/opentui-bionic
	cp -f tools/prebuilt/libopentui-bionic.so artifacts/transplant/opentui-bionic/libopentui.so

	make transplant VER="$VERSION"
	make deb-native VER="$VERSION"
	if [ "$DO_PACMAN" = 1 ]; then
		make pacman-native VER="$VERSION"
	fi

	DEB="packing/dpkg-native/opencode_${VERSION}_aarch64.deb"
	[ -f "$DEB" ] || die "package was not produced: $DEB"
fi

if [ "$DO_INSTALL" = 1 ]; then
	log "installing $DEB"
	dpkg -i "$DEB"
	log "installed version: $(opencode --version 2>/dev/null || echo unknown)"
else
	log "build complete (not installed): $DEB"
fi
