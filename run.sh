#!/bin/bash
#
# run.sh - Kernel builder for Realme Even (MT6768) - KernelSU-Next (legacy)
#
# Usage:
#   ./run.sh              interactive menu (default)
#   ./run.sh --build      one-shot build + package (auto version bump)
#   ./run.sh --force      with --build: overwrite existing zip
#   ./run.sh --no-package with --build: build only
#   ./run.sh --clean      remove out/ and flashable zips
#   ./run.sh --push       push latest zip to device
#
# Toolchain resolution order:
#   1. ./prebuilts-clang-proton  (kdrag0n/proton-clang)
#   2. ../../../prebuilts/clang/host/linux-x86/mylitle-clang  (LineageOS tree)
#   3. $KERNEL_CLANG  (explicit override)
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

info()  { echo -e "${GREEN}[*]${NC} $*"; }
warn()  { echo -e "${YELLOW}[!]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; }
header(){ echo -e "\n${CYAN}${BOLD}═══ $* ═══${NC}\n"; }

# --- Config ---
DEFCONFIG="RMX3191_defconfig"
ARCH="arm64"
JOBS="$(nproc)"
OUT_DIR="$SCRIPT_DIR/out"
ANYKERNEL_DIR="$SCRIPT_DIR/anykernel3"
ANYKERNEL_REPO="https://github.com/osm0sis/AnyKernel3.git"
ANYKERNEL_CONFIG="$SCRIPT_DIR/config/anykernel.sh"
PROTON_DIR="$SCRIPT_DIR/prebuilts-clang-proton"
PROTON_REPO="https://github.com/kdrag0n/proton-clang.git"
LINEAGE_CLANG="$(realpath "$SCRIPT_DIR/../../../prebuilts/clang/host/linux-x86/mylitle-clang" 2>/dev/null || true)"
ZIP_PREFIX="Stock-Even-RUI2"
VERSION_FILE="$SCRIPT_DIR/.kernel_zip_version"
KERNEL_STRING="Stock Kernel Even (Migrated + KSUNext) by rjfahad"

FORCE=0
DO_PACKAGE=1
MODE="menu"

# --- Version handling ---
read_version() {
    local v="1.0"
    if [ -f "$VERSION_FILE" ]; then
        v="$(tr -d '[:space:]' < "$VERSION_FILE")"
    fi
    [[ "$v" =~ ^[0-9]+(\.[0-9]+)?$ ]] || v="1.0"
    echo "$v"
}

bump_version() {
    local major="${1%%.*}" minor="${1#*.}"
    if [ "$major" = "$1" ]; then
        minor="0"
    fi
    [[ "$major" =~ ^[0-9]+$ ]] || major="1"
    [[ "$minor" =~ ^[0-9]+$ ]] || minor="0"
    echo "$major.$((minor + 1))"
}

zip_name_for_version() {
    echo "${ZIP_PREFIX}-v${1}.zip"
}

# --- Root solution ---
detect_root_solution() {
    if [ -f "$SCRIPT_DIR/KernelSU-Next/kernel/Kconfig" ]; then
        echo "ksunext"
    elif git submodule status 2>/dev/null | grep -q '^-.*KernelSU-Next'; then
        echo "ksunext (uninitialized)"
    else
        echo "none"
    fi
}

ensure_root_solution() {
    if [ -f "$SCRIPT_DIR/KernelSU-Next/kernel/Kconfig" ]; then
        return 0
    fi
    if git submodule status 2>/dev/null | grep -q '^-.*KernelSU-Next'; then
        info "Initializing KernelSU-Next submodule..."
        git submodule update --init --recursive
    fi
    if [ ! -f "$SCRIPT_DIR/KernelSU-Next/kernel/Kconfig" ]; then
        error "KernelSU-Next not available."
        error "Run menu -> [1] Setup Workspace, or:"
        error "  git submodule update --init --recursive"
        return 1
    fi
}

# --- Toolchain ---
detect_toolchain() {
    if [ -x "$PROTON_DIR/bin/clang" ]; then
        echo "proton"
    elif [ -n "$LINEAGE_CLANG" ] && [ -x "$LINEAGE_CLANG/bin/clang" ]; then
        echo "lineage"
    elif [ -n "${KERNEL_CLANG:-}" ] && [ -x "$KERNEL_CLANG/bin/clang" ]; then
        echo "custom"
    else
        echo "none"
    fi
}

setup_path() {
    local tc
    tc="$(detect_toolchain)"
    case "$tc" in
        proton)  export PATH="$PROTON_DIR/bin:$PATH"; info "Toolchain: Proton Clang ($PROTON_DIR)" ;;
        lineage) export PATH="$LINEAGE_CLANG/bin:$PATH"; info "Toolchain: mylitle-clang ($LINEAGE_CLANG)" ;;
        custom)  export PATH="$KERNEL_CLANG/bin:$PATH"; info "Toolchain: $KERNEL_CLANG" ;;
        *)
            error "No toolchain found."
            error "Install one of:"
            error "  - ./prebuilts-clang-proton  (menu -> [1] Setup Workspace)"
            error "  - \$KERNEL_CLANG=<path> ./run.sh"
            return 1
            ;;
    esac
    clang --version 2>/dev/null | head -1 | sed 's/^/    /'
}

# --- Device tree compiler ---
setup_dtc() {
    if command -v dtc >/dev/null 2>&1; then
        return 0
    fi
    if [ -x "$OUT_DIR/scripts/dtc/dtc" ]; then
        export PATH="$OUT_DIR/scripts/dtc:$PATH"
        return 0
    fi
    info "Building host dtc from kernel sources..."
    make O="$OUT_DIR" ARCH=$ARCH CC=clang HOSTCC=clang CROSS_COMPILE=aarch64-linux-gnu- scripts/dtc/ >/dev/null
    if [ ! -x "$OUT_DIR/scripts/dtc/dtc" ]; then
        error "Failed to build in-tree dtc"
        return 1
    fi
    export PATH="$OUT_DIR/scripts/dtc:$PATH"
}

# --- AnyKernel3 ---
setup_anykernel() {
    if [ ! -d "$ANYKERNEL_DIR" ]; then
        info "Cloning AnyKernel3..."
        git clone --depth=1 "$ANYKERNEL_REPO" "$ANYKERNEL_DIR"
    fi
    if [ -f "$ANYKERNEL_CONFIG" ]; then
        cp "$ANYKERNEL_CONFIG" "$ANYKERNEL_DIR/anykernel.sh"
        info "Applied device anykernel.sh template"
    else
        warn "config/anykernel.sh not found; using stock AnyKernel3 template"
    fi
}

# --- Build ---
build_kernel() {
    info "Defconfig: $DEFCONFIG"
    make O="$OUT_DIR" ARCH=$ARCH CC=clang HOSTCC=clang CROSS_COMPILE=aarch64-linux-gnu- "$DEFCONFIG"

    setup_dtc

    info "Building kernel with $JOBS jobs..."
    local start_time
    start_time="$(date +%s)"
    make O="$OUT_DIR" ARCH=$ARCH CC=clang HOSTCC=clang CROSS_COMPILE=aarch64-linux-gnu- \
        -j"$JOBS" Image.gz-dtb
    local end_time
    end_time="$(date +%s)"
    local elapsed=$(( end_time - start_time ))
    local kernel_size
    kernel_size="$(ls -lh "$OUT_DIR/arch/arm64/boot/Image.gz-dtb" | awk '{print $5}')"
    info "Build complete in ${elapsed}s -> $OUT_DIR/arch/arm64/boot/Image.gz-dtb ($kernel_size)"
}

# --- Packaging ---
package_zip() {
    local version="$1"
    local zip_name
    zip_name="$(zip_name_for_version "$version")"
    local output_path="$SCRIPT_DIR/$zip_name"

    if [ ! -f "$OUT_DIR/arch/arm64/boot/Image.gz-dtb" ]; then
        error "Image.gz-dtb not found. Build first."
        return 1
    fi

    setup_anykernel

    cp "$OUT_DIR/arch/arm64/boot/Image.gz-dtb" "$ANYKERNEL_DIR/Image.gz-dtb"
    sed -i "s/^kernel.string=.*/kernel.string=$KERNEL_STRING/" "$ANYKERNEL_DIR/anykernel.sh"

    rm -f "$output_path"
    info "Packaging $zip_name..."
    ( cd "$ANYKERNEL_DIR" && zip -r9 "$output_path" . \
        -x ".git/*" -x ".github/*" -x "README.md" -x "LICENSE" >/dev/null )
    printf '%s\n' "$version" > "$VERSION_FILE"

    local zip_size
    zip_size="$(ls -lh "$output_path" | awk '{print $5}')"
    info "Flashable zip: $output_path ($zip_size)"
}

clean_all() {
    header "Clean"
    info "Removing $OUT_DIR ..."
    rm -rf "$OUT_DIR"
    info "Removing ${ZIP_PREFIX}-v*.zip ..."
    rm -f "${ZIP_PREFIX}-v"*.zip
    info "Removing $VERSION_FILE ..."
    rm -f "$VERSION_FILE"
    info "Clean complete"
}

# --- 1. Setup Workspace ---
setup_workspace() {
    header "Setup Workspace"

    if [ "$(detect_toolchain)" = "none" ]; then
        info "Cloning Proton Clang..."
        git clone --depth=1 "$PROTON_REPO" "$PROTON_DIR"
        if [ -f "$PROTON_DIR/bin/ld" ]; then
            mv "$PROTON_DIR/bin/ld" "$PROTON_DIR/bin/ld.bak"
            info "Renamed Proton ld -> ld.bak"
        fi
        info "Proton Clang installed"
    else
        info "Toolchain already present ($(detect_toolchain))"
    fi

    setup_anykernel

    if ! ensure_root_solution; then
        return 1
    fi

    if setup_path; then
        info "Workspace setup complete"
    else
        error "Workspace setup failed"
    fi
}

# --- 2. Build & Package ---
build_and_package() {
    header "Build & Package"

    if ! setup_path; then
        return 1
    fi

    if ! ensure_root_solution; then
        return 1
    fi

    local root_sol build_version zip_name output_path
    root_sol="$(detect_root_solution)"
    build_version="$(read_version)"
    zip_name="$(zip_name_for_version "$build_version")"
    output_path="$SCRIPT_DIR/$zip_name"

    info "Root solution: $root_sol"
    info "Output: $zip_name"
    echo ""

    if [ -f "$output_path" ]; then
        warn "Version v${build_version} already exists: $zip_name"
        while true; do
            read -rp "  [v] bump version  [o] overwrite  [c] cancel: " version_choice
            case "$version_choice" in
                v|V)
                    while :; do
                        build_version="$(bump_version "$build_version")"
                        zip_name="$(zip_name_for_version "$build_version")"
                        output_path="$SCRIPT_DIR/$zip_name"
                        if [ ! -f "$output_path" ]; then
                            break
                        fi
                    done
                    info "Using version v${build_version}"
                    info "Output: $zip_name"
                    break
                    ;;
                o|O)
                    rm -f "$output_path"
                    info "Overwriting existing zip"
                    break
                    ;;
                c|C)
                    return 0
                    ;;
                *)
                    warn "Please choose v, o, or c."
                    ;;
            esac
        done
    fi

    build_kernel
    package_zip "$build_version"
}

# --- 3. Push to Device ---
push_to_device() {
    header "Push to Device"

    if ! adb devices 2>/dev/null | grep -q "device$"; then
        error "No device connected"
        return 1
    fi

    local version
    version="$(read_version)"
    local zip_name
    zip_name="$(zip_name_for_version "$version")"
    local zip_path="$SCRIPT_DIR/$zip_name"

    if [ ! -f "$zip_path" ]; then
        error "$zip_name not found. Build & Package first."
        return 1
    fi

    info "Pushing $zip_name to /sdcard/..."
    adb push "$zip_path" /sdcard/
    info "Done. Flash from recovery."
}

# --- Menu ---
show_menu() {
    local compiler root_sol build_version
    compiler="$(detect_toolchain)"
    root_sol="$(detect_root_solution)"
    build_version="$(read_version)"

    header "Realme Even Kernel Builder"
    echo -e "  Compiler:   ${BOLD}${compiler}${NC}"
    echo -e "  Root:       ${BOLD}${root_sol}${NC}"
    echo -e "  Zip Ver:    ${BOLD}v${build_version}${NC}"
    echo -e "  Branch:     ${BOLD}$(git branch --show-current 2>/dev/null || echo detached)${NC}"
    echo ""
    echo "  [1] Setup Workspace"
    echo "  [2] Build & Package"
    echo "  [3] Push to Device"
    echo "  [4] Clean"
    echo "  [0] Exit"
    echo ""
}

main_menu() {
    while true; do
        show_menu
        read -rp "  > " choice
        case "$choice" in
            1) setup_workspace ;;
            2) build_and_package ;;
            3) push_to_device ;;
            4) clean_all ;;
            0) exit 0 ;;
            *) error "Invalid choice" ;;
        esac
        echo ""
        read -rp "  Press Enter to continue..."
    done
}

# --- Main ---
one_shot_build() {
    local version
    version="$(read_version)"

    if ! setup_path; then
        exit 1
    fi

    if ! ensure_root_solution; then
        exit 1
    fi

    if [ "$DO_PACKAGE" = 1 ] && [ "$FORCE" = 0 ] && [ -f "$(zip_name_for_version "$version")" ]; then
        warn "v${version} zip already exists, bumping to next version"
        version="$(bump_version "$version")"
        info "Using version v${version}"
    fi

    build_kernel

    if [ "$DO_PACKAGE" = 1 ]; then
        package_zip "$version"
    fi
}

for arg in "$@"; do
    case "$arg" in
        --build)      MODE="build" ;;
        --force)      FORCE=1 ;;
        --no-package) DO_PACKAGE=0 ;;
        --clean)      MODE="clean" ;;
        --push)       MODE="push" ;;
        --menu)       MODE="menu" ;;
        *)
            error "Unknown argument: $arg"
            echo "Usage: $0 [--build] [--force] [--no-package] [--clean] [--push] [--menu]"
            exit 1
            ;;
    esac
done

case "$MODE" in
    build) one_shot_build ;;
    clean) clean_all ;;
    push)  push_to_device ;;
    menu)  main_menu ;;
esac