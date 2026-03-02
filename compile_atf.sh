#!/bin/sh

TOOLCHAIN=aarch64-linux-gnu-

ATFCFG_DIR="${ATFCFG_DIR:-mt798x_atf}"
OUTPUT_DIR="${OUTPUT_DIR:-output_bl2}"

VERSION=${VERSION:-2025}

if [ -z "$ATF_DIR" ]; then
    if [ "$VERSION" = "2025" ]; then
        ATF_DIR=atf-20250711
    elif [ "$VERSION" = "2026" ]; then
        ATF_DIR=atf-20260123
    else
        echo "Error: Unsupported VERSION. Please specify VERSION=2025/2026 or set ATF_DIR."
        exit 1
    fi
fi

if [ ! -d "$ATFCFG_DIR" ]; then
    echo "Error: ATFCFG_DIR '$ATFCFG_DIR' not found."
    exit 1
fi

if [ ! -d "$ATF_DIR" ]; then
    echo "Error: ATF_DIR '$ATF_DIR' not found."
    exit 1
fi

command -v "${TOOLCHAIN}gcc" >/dev/null 2>&1
[ "$?" != "0" ] && { echo "${TOOLCHAIN}gcc not found!"; exit 1; }
export CROSS_COMPILE="$TOOLCHAIN"

if [ -e "$ATF_DIR/makefile" ]; then
    ATF_MKFILE="makefile"
else
    ATF_MKFILE="Makefile"
fi

mkdir -p "$OUTPUT_DIR"
mkdir -p "$ATF_DIR/build"

CONFIG_LIST=$(ls "$ATFCFG_DIR"/*.config 2>/dev/null)
if [ -z "$CONFIG_LIST" ]; then
    echo "Error: no .config files found in $ATFCFG_DIR"
    exit 1
fi

SUCCESS_COUNT=0
FAIL_COUNT=0
FAILED_CONFIGS=""

for cfg_file in $CONFIG_LIST; do
    cfg_name=$(basename "$cfg_file")
    cfg_base=${cfg_name%.config}
    # Example filenames:
    #   mt7981-ddr3-bga-ram.config  -> soc=mt7981
    #   atf-mt7986-ddr4-ram.config  -> soc=mt7986
    soc=$(echo "$cfg_base" | sed -e 's/^atf-//' | cut -d'-' -f1)
    echo "Building BL2: $cfg_name (soc=$soc)"
    rm -rf "$ATF_DIR/build"
    mkdir -p "$ATF_DIR/build"
    cp -f "$cfg_file" "$ATF_DIR/build/.config"
    echo "Starting build for $cfg_name ..."
    echo "----------------------------------------"
    build_ok=1
    make -C "$ATF_DIR" olddefconfig || build_ok=0
    make -C "$ATF_DIR" -f "$ATF_MKFILE" clean CONFIG_CROSS_COMPILER="$TOOLCHAIN" CROSS_COMPILER="$TOOLCHAIN" || build_ok=0
    if [ "$build_ok" = "1" ]; then
        make -C "$ATF_DIR" -f "$ATF_MKFILE" all CONFIG_CROSS_COMPILER="$TOOLCHAIN" CROSS_COMPILER="$TOOLCHAIN" -j $(nproc) || build_ok=0
    fi

    if [ "$build_ok" = "1" ] && [ -f "$ATF_DIR/build/${soc}/release/bl2.img" ]; then
        src_file="$ATF_DIR/build/${soc}/release/bl2.img"
        bl2_md5=$(md5sum "$src_file" | awk '{print $1}')
        out_name="bl2-${cfg_base}-Yuzhii_md5-${bl2_md5}.img"
        cp -f "$src_file" "$OUTPUT_DIR/$out_name"
        echo "$out_name build done"
        echo "----------------------------------------"
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    elif [ "$build_ok" = "1" ] && [ -f "$ATF_DIR/build/${soc}/release/bl2.bin" ]; then
        src_file="$ATF_DIR/build/${soc}/release/bl2.bin"
        bl2_md5=$(md5sum "$src_file" | awk '{print $1}')
        out_name="bl2-${cfg_base}-Yuzhii_md5-${bl2_md5}.bin"
        cp -f "$src_file" "$OUTPUT_DIR/$out_name"
        echo "Warning: bl2.img not found, fallback to bl2.bin"
        echo "$out_name build done"
        echo "----------------------------------------"
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    else
        echo "bl2 build fail for $cfg_name! (neither bl2.img nor bl2.bin found)"
        echo "----------------------------------------"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        FAILED_CONFIGS="$FAILED_CONFIGS $cfg_name"
    fi
done

echo "Build summary: success=$SUCCESS_COUNT, failed=$FAIL_COUNT"
if [ "$FAIL_COUNT" -gt 0 ]; then
    echo "Failed configs:$FAILED_CONFIGS"
fi

if [ "$SUCCESS_COUNT" -eq 0 ]; then
    echo "Error: all BL2 builds failed."
    exit 1
fi

echo "At least one BL2 build succeeded, continue workflow."
