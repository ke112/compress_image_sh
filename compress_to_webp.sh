#!/bin/bash

# --- 配置参数 ---
image_dir=$1
quality="80"       # 建议 75-85 之间，100 往往无法减小体积
min_size_kb=100    # 调整阈值为 100KB，500KB 可能跳过太多图片

# --- 统计变量 ---
imageNum=0
pngNum=0
jpgNum=0
jpegNum=0
webpNum=0
heicNum=0
compressNum=0
skipNum=0

# --- 颜色定义 ---
function log() {
  echo -e "\033[42;97m $* \033[0m"
}

function warn() {
  echo -e "\033[41;97m [错误] $* \033[0m"
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
function get_file_size_kb() {
  local file="$1"
  local size_bytes=0
  if [[ "$OSTYPE" == "darwin"* ]]; then
    size_bytes=$(stat -f%z "$file" 2>/dev/null || echo 0)
  else
    size_bytes=$(stat -c%s "$file" 2>/dev/null || echo 0)
  fi
  echo $((size_bytes / 1024))
}

function handle_file() {
  local file="$1"
  local filename=$(basename "$file")
  local extension="${filename##*.}"
  local base_name="${file%.*}"
  
  # 统一转为小写匹配
  local ext_lower=$(echo "$extension" | tr '[:upper:]' '[:lower:]')
  
  if [[ "$ext_lower" =~ ^(png|jpg|jpeg|webp|heic)$ ]]; then
    imageNum=$((imageNum + 1))
    
    # 统计各格式数量
    case "$ext_lower" in
      png) pngNum=$((pngNum + 1)) ;;
      jpg) jpgNum=$((jpgNum + 1)) ;;
      jpeg) jpegNum=$((jpegNum + 1)) ;;
      webp) webpNum=$((webpNum + 1)) ;;
      heic) heicNum=$((heicNum + 1)) ;;
    esac

    local size_kb=$(get_file_size_kb "$file")
    if [ $size_kb -gt $min_size_kb ]; then
      local newfile="${base_name}.webp"
      local temp_output="${file}.tmp.webp"
      
      # 执行转换
      cwebp -quiet -q "$quality" -mt "$file" -o "$temp_output"

      # 检查转换是否成功且文件大小是否有效
      if [ $? -eq 0 ] && [ -f "$temp_output" ] && [ $(get_file_size_kb "$temp_output") -gt 0 ]; then
        if [[ "$ext_lower" == "webp" ]]; then
          mv "$temp_output" "$file"
          echo "Re-encoded $file"
        else
          mv "$temp_output" "$newfile"
          # 只有新文件生成成功才删除旧文件
          rm -f "$file"
          echo "Converted $file to $newfile"
        fi
        compressNum=$((compressNum + 1))
      else
        warn "转换失败: $file"
        [ -f "$temp_output" ] && rm -f "$temp_output"
      fi
    else
      echo "Skipped $file (size ${size_kb}KB <= ${min_size_kb}KB)"
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
  start_size=$(du -sh "$image_dir" | awk '{print $1}')
  traverse "$image_dir"
  end_size=$(du -sh "$image_dir" | awk '{print $1}')
elif [ -f "$image_dir" ]; then
  start_size=$(du -sh "$image_dir" | awk '{print $1}')
  handle_file "$image_dir"
  end_size=$(du -sh "$image_dir" | awk '{print $1}')
else
  warn "输入路径不存在: $image_dir"
  exit 1
fi

# --- 统计报告 ---
echo -e "\n"
log "==== 本次共检索到 ${imageNum} 张图片, 处理了 ${compressNum} 张, 跳过了 ${skipNum} 张"
log "==== 详情: PNG:${pngNum} | JPG:${jpgNum} | JPEG:${jpegNum} | WEBP:${webpNum} | HEIC:${heicNum}"
log "==== 压缩前总大小: $start_size"
log "==== 压缩后总大小: $end_size"
showTime
echo -e "\n"
