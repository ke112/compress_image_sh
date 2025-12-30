#!/bin/bash

# 获取脚本所在目录的绝对路径
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# 获取项目根目录（脚本目录的上上级目录）
PROJECT_ROOT=$(cd "${SCRIPT_DIR}/../.." && pwd)

# --- 配置参数 ---
image_dir="$PROJECT_ROOT/assets"
quality="80"       # 建议 75-85 之间，100 往往无法减小体积
min_size_kb=100    # 调整阈值为 100KB，500KB 可能跳过太多图片
# 白名单，不会被压缩
white_list=()

# --- 统计变量 ---
imageNum=0
pngNum=0
jpgNum=0
jpegNum=0
webpNum=0
heicNum=0
svgNum=0
compressNum=0
skipNum=0

# --- 颜色定义 ---
function log() {
  # 统一使用 printf 避免部分 shell 下 echo -e 的兼容性问题
  printf "\033[42;97m %s \033[0m\n" "$*"
}

function success_log() {
  # 绿色背景，黑色文字，用于醒目显示处理成功的文件
  printf "\033[42;30m %s \033[0m\n" "$*"
}

function warn() {
  printf "\033[41;97m [错误] %s \033[0m\n" "$*"
}

# --- 环境检查 ---
if ! command -v cwebp &> /dev/null; then
  warn "未找到 cwebp 工具。请先安装：brew install webp (macOS) 或 apt-get install webp (Linux)"
  exit 1
fi

if [ -z "$image_dir" ]; then
  warn "请提供图片文件夹路径。用法: sh compress_to_webp.sh <dir_path>"
  exit 1
fi

# --- 工具函数 ---
function is_in_whitelist() {
  local target="$1"
  for item in "${white_list[@]}"; do
    if [[ "$target" == "$item" ]]; then
      return 0 # 在白名单中
    fi
  done
  return 1 # 不在白名单中
}

function get_file_size_bytes() {
  local file="$1"
  if [[ "$OSTYPE" == "darwin"* ]]; then
    stat -f%z "$file" 2>/dev/null || echo 0
  else
    stat -c%s "$file" 2>/dev/null || echo 0
  fi
}

# 辅助函数：将字节转换为易读格式
function format_size() {
  local bytes=$1
  if [ $bytes -lt 1024 ]; then
    echo "${bytes}B"
  elif [ $bytes -lt 1048576 ]; then
    printf "%.2fKB" $(echo "scale=2; $bytes/1024" | bc)
  else
    printf "%.2fMB" $(echo "scale=2; $bytes/1048576" | bc)
  fi
}

# 辅助函数：获取目录的总大小（字节）
function get_dir_size_bytes() {
  local dir="$1"
  if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    find "$dir" -type f -exec stat -f%z {} + 2>/dev/null | awk '{sum += $1} END {print sum}' || echo 0
  else
    # Linux
    du -bc "$dir" 2>/dev/null | tail -1 | awk '{print $1}' || echo 0
  fi
}

# 辅助函数：格式化目录大小显示
function format_dir_size() {
  local bytes=$1
  if [ "$bytes" -lt 1024 ]; then
    printf "%.2fB" "$bytes"
  elif [ "$bytes" -lt 1048576 ]; then
    printf "%.2fKB" $(echo "scale=2; $bytes/1024" | bc -l 2>/dev/null || echo "0")
  elif [ "$bytes" -lt 1073741824 ]; then
    printf "%.2fMB" $(echo "scale=2; $bytes/1048576" | bc -l 2>/dev/null || echo "0")
  else
    printf "%.2fGB" $(echo "scale=2; $bytes/1073741824" | bc -l 2>/dev/null || echo "0")
  fi
}

function handle_file() {
  local file="$1"
  local filename=$(basename "$file")

  # 检查白名单
  if is_in_whitelist "$filename"; then
    echo "Skipped $file (Whitelist)"
    skipNum=$((skipNum + 1))
    return
  fi

  local extension="${filename##*.}"
  local base_name="${file%.*}"
  
  # 统一转为小写匹配
  local ext_lower=$(echo "$extension" | tr '[:upper:]' '[:lower:]')
  
  if [[ "$ext_lower" =~ ^(png|jpg|jpeg|webp|heic|svg)$ ]]; then
    imageNum=$((imageNum + 1))
    
    # 统计各格式数量
    case "$ext_lower" in
      png) pngNum=$((pngNum + 1)) ;;
      jpg) jpgNum=$((jpgNum + 1)) ;;
      jpeg) jpegNum=$((jpegNum + 1)) ;;
      webp) webpNum=$((webpNum + 1)) ;;
      heic) heicNum=$((heicNum + 1)) ;;
      svg) svgNum=$((svgNum + 1)) ;;
    esac

    # 如果是webp格式，直接跳过不压缩
    if [[ "$ext_lower" == "webp" ]]; then
      echo "Skipped $file (WebP format, no need to compress)"
      skipNum=$((skipNum + 1))
      return
    fi

    local size_bytes=$(get_file_size_bytes "$file")
    local min_size_bytes=$((min_size_kb * 1024))

    if [ "$size_bytes" -gt "$min_size_bytes" ]; then
      local newfile="${base_name}.webp"
      local temp_output="${file}.tmp.webp"
      local status=0
      
      # 执行转换
      if [[ "$ext_lower" == "svg" ]]; then
        # SVG 转换逻辑
        if command -v rsvg-convert &> /dev/null; then
          rsvg-convert --format=webp "$file" -o "$temp_output" || status=$?
        elif command -v magick &> /dev/null; then
          magick "$file" "$temp_output" || status=$?
        elif command -v convert &> /dev/null; then
          convert "$file" "$temp_output" || status=$?
        else
          warn "跳过 SVG: 未找到 rsvg-convert 或 ImageMagick。请安装 librsvg 或 imagemagick"
          return
        fi
      else
        # 其他格式继续使用 cwebp
        cwebp -quiet -q "$quality" -mt "$file" -o "$temp_output" || status=$?
      fi

      # 立即检查转换结果，避免 $? 被后续命令覆盖
      if [ $status -ne 0 ] || [ ! -f "$temp_output" ]; then
        warn "转换失败 (退出码: $status): $file"
        [ -f "$temp_output" ] && rm -f "$temp_output"
        return
      fi

      local new_size_bytes=$(get_file_size_bytes "$temp_output")

      # 核心逻辑：比较大小后决定保留哪个文件
      if [ "$new_size_bytes" -gt 0 ] && [ "$new_size_bytes" -lt "$size_bytes" ]; then
        # 新文件比源文件小，保留新文件，删除源文件
        if [[ "$ext_lower" == "webp" ]]; then
          # 对于webp文件，直接覆盖
          mv "$temp_output" "$file"
          success_log "Re-encoded $file ($(format_size $size_bytes) -> $(format_size $new_size_bytes), 压缩率: $(echo "scale=2; ($size_bytes-$new_size_bytes)*100/$size_bytes" | bc)%)"
        else
          # 对于其他格式，先创建webp文件，再删除源文件
          mv "$temp_output" "$newfile"
          rm -f "$file"
          success_log "Converted $file to $newfile ($(format_size $size_bytes) -> $(format_size $new_size_bytes), 压缩率: $(echo "scale=2; ($size_bytes-$new_size_bytes)*100/$size_bytes" | bc)%)"
        fi
        compressNum=$((compressNum + 1))
      else
        # 新文件不满足条件（压缩后比原图还大），保留源文件，删除webp文件
        echo "Skipped $file (WebP not smaller: $(format_size $new_size_bytes) >= $(format_size $size_bytes), 保留原文件)"
        rm -f "$temp_output"
        skipNum=$((skipNum + 1))
      fi
    else
      echo "Skipped $file (size $(format_size $size_bytes) <= $(format_size $min_size_bytes))"
      skipNum=$((skipNum + 1))
    fi
  fi
}

function traverse() {
  local dir="$1"
  # 确保目录存在且可读
  if [ ! -d "$dir" ]; then return; fi
  
  for file in "$dir"/*; do
    if [ -d "$file" ]; then
      traverse "$file"
    elif [ -f "$file" ]; then
      handle_file "$file"
    fi
  done
}

function showTime() {
  local endTime=$(date +%Y-%m-%d-%H:%M:%S)
  local endTime_s=$(date +%s)
  local sumTime=$((endTime_s - startTime_s))
  log "==== 开始时间: $startTime"
  log "==== 结束时间: $endTime"
  local endDes='==== 总共用时:'
  if [ $sumTime -gt 60 ]; then
    local min=$((sumTime / 60))
    local sec=$((sumTime % 60))
    log "${endDes} ${min}分${sec}秒"
  else
    log "${endDes} ${sumTime}秒"
  fi
}

# --- 执行开始 ---
startTime=$(date +%Y-%m-%d-%H:%M:%S)
startTime_s=$(date +%s)

# 显示压缩前的文件夹大小
if [ -d "$image_dir" ]; then
  start_size_bytes=$(get_dir_size_bytes "$image_dir")
  start_size=$(format_dir_size "$start_size_bytes")
  traverse "$image_dir"
  end_size_bytes=$(get_dir_size_bytes "$image_dir")
  end_size=$(format_dir_size "$end_size_bytes")
elif [ -f "$image_dir" ]; then
  start_size_bytes=$(get_file_size_bytes "$image_dir")
  start_size=$(format_dir_size "$start_size_bytes")
  handle_file "$image_dir"
  end_size_bytes=$(get_file_size_bytes "$image_dir")
  end_size=$(format_dir_size "$end_size_bytes")
else
  warn "输入路径不存在: $image_dir"
  exit 1
fi

# --- 统计报告 ---
printf "\n\n"
log "==== 本次共检索到 ${imageNum} 张图片, 处理了 ${compressNum} 张, 跳过了 ${skipNum} 张"
log "==== 详情: PNG:${pngNum} | JPG:${jpgNum} | JPEG:${jpegNum} | WEBP:${webpNum} | HEIC:${heicNum} | SVG:${svgNum}"
log "==== 压缩前总大小: $start_size"
log "==== 压缩后总大小: $end_size"
showTime
printf "\n\n"
