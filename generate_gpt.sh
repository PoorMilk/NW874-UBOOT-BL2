#!/bin/bash

# 设置输入和输出文件夹路径
input_folder="./mt798x_gpt"
input_folder_show="./mt798x_gpt_bin"
output_folder="./output_gpt"

# 实际几个 ATF 版本在 GPT 工具上无区别
VERSION=${VERSION:-2025}

if [ "$VERSION" = "2022" ]; then
    tools_folder="./atf-20220606-637ba581b/tools/dev/gpt_editor"
elif [ "$VERSION" = "2023" ]; then
    tools_folder="./atf-20231013-0ea67d76a/tools/dev/gpt_editor"
elif [ "$VERSION" = "2024" ]; then
    tools_folder="./atf-20240117-bacca82a8/tools/dev/gpt_editor"
elif [ "$VERSION" = "2025" ]; then
    tools_folder="./atf-20250711/tools/dev/gpt_editor"
elif [ "$VERSION" = "2026" ]; then
    tools_folder="./atf-20260123/tools/dev/gpt_editor"
else
    echo "Error: Unsupported VERSION. Please specify VERSION=2022/2023/2024/2025/2026."
    exit 1
fi

# Check if Python is installed on the system
echo "Trying python2.7..."
command -v python2.7
[ "$?" != "0" ] && { echo "Error: Python2.7 is not installed on this system."; exit 0; }

echo "Using GPT tools from: $tools_folder"

# 确保输出文件夹存在，不存在则创建
mkdir -p "$output_folder"
mkdir -p "$output_folder/picture"
mkdir -p "$output_folder/info"

# 成功/失败计数
built_count=0
fail_count=0
png_built_count=0
png_fail_count=0

# DRAW=1 时用于生成分区布局 PNG（建议使用 python3）
if [ "$DRAW" = "1" ]; then
    echo "Trying python3..."
    command -v python3
    [ "$?" != "0" ] && { echo "Error: Python3 is not installed on this system."; exit 0; }
fi

if [ "$SHOW" = "1" ]; then
    # 遍历输入文件夹中的所有 bin/img 文件
    for bin_file in "$input_folder_show"/*.bin "$input_folder_show"/*.img; do
        # 如果文件不存在，跳过
        [ -e "$bin_file" ] || continue

        # 提取文件名（不包含路径和扩展名）
        filename=$(basename -- "$bin_file")
        filename_no_extension="${filename%.*}"

        # 构建输出文本文件路径
        output_file="$output_folder/info/${filename_no_extension}_gptinfo.txt"

        echo
        echo "=============================="
        echo
        echo "Processing: $filename"
        echo
        echo "=============================="
        echo

        # 执行 Python 命令获取 gpt 信息，并写入输出文本
        python2.7 "$tools_folder/mtk_gpt.py" --show "$bin_file" > "$output_file"

        if [ -f "$output_file" ]; then
            echo "Done: $filename, info written to: $output_file"
            built_count=$((built_count + 1))
        else
            echo "Failed: $filename (output not found: $output_file)"
            fail_count=$((fail_count + 1))
        fi

        echo
        echo "=============================="
        echo
    done

    echo "All files processed"
    echo "Success: $built_count  Failed: $fail_count"
else
    # 遍历输入文件夹中的所有json文件
    for json_file in "$input_folder"/*.json; do
        # 提取文件名（不包含路径和扩展名）
        filename=$(basename -- "$json_file")
        filename_no_extension="${filename%.*}"

        # 构建输出文件路径
        output_file="$output_folder/gpt-$filename_no_extension.bin"
        output_file_sdmmc="$output_folder/gpt-$filename_no_extension.sdmmc.bin"
        output_png="$output_folder/picture/gpt-$filename_no_extension.png"

        echo
        echo "=============================="
        echo
        echo "Processing: $filename"
        echo
        echo "=============================="
        echo

        # 执行Python命令
        if [ "$SDMMC" = "1" ]; then
            python2.7 "$tools_folder/mtk_gpt.py" --i "$json_file" --o "$output_file_sdmmc" --sdmmc
            built_out_file_raw="$output_file_sdmmc"
        else
            python2.7 "$tools_folder/mtk_gpt.py" --i "$json_file" --o "$output_file"
            built_out_file_raw="$output_file"
        fi

        # 可选：生成布局 PNG
        if [ "$DRAW" = "notitle" ]; then
            python3 "$tools_folder/partition_layout.py" --i "$json_file" --o "$output_png"
        fi
        if [ "$DRAW" = "1" ]; then
            python3 "$tools_folder/partition_layout.py" --i "$json_file" --o "$output_png" --title
        fi

        # 输出文件存在性检查（GPT bin）
        if [ -f "$built_out_file_raw" ]; then
            gpt_md5=$(md5sum "$built_out_file_raw" | awk '{print $1}')
            built_base=$(basename -- "$built_out_file_raw")
            built_name_no_extension="${built_base%.*}"
            built_extension="${built_base##*.}"
            built_out_file="$output_folder/${built_name_no_extension}-Yuzhii_md5-${gpt_md5}.${built_extension}"
            mv -f "$built_out_file_raw" "$built_out_file"
            echo "Built: $built_out_file"
            built_count=$((built_count + 1))
        else
            echo "Error: output not found: $built_out_file_raw"
            fail_count=$((fail_count + 1))
        fi

        # 输出文件存在性检查（PNG，可选）
        if [ "$DRAW" = "1" ]; then
            if [ -f "$output_png" ]; then
                echo "Built: $output_png"
                png_built_count=$((png_built_count + 1))
            else
                echo "Error: output not found: $output_png"
                png_fail_count=$((png_fail_count + 1))
            fi
        fi

        # 输出执行结果
        echo
        echo "=============================="
        echo
        echo "Converted: $filename"
        echo
        echo "=============================="
        echo
    done

    echo "All files converted"
    echo "GPT bin Success: $built_count  Failed: $fail_count"
    if [ "$DRAW" = "1" ]; then
        echo "PNG Success: $png_built_count  Failed: $png_fail_count"
    fi
fi