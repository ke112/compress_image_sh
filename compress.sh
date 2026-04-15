#!/bin/bash
#
# 图片批量降采样 / WebP 重编码
# 用法: compress.sh <图片目录>
# 输出: 在同级生成 <原目录名>_<时间戳>_resized 副本并在副本上处理，原目录不动

set -u

image_dir=${1:-}
if [[ -z "$image_dir" || ! -d "$image_dir" ]]; then
  echo "用法: $0 <图片目录>"
  exit 1
fi

# 去掉可能的结尾斜杠
image_dir="${image_dir%/}"

# 目标最大边（像素）
target_size=1024
# WebP 重编码质量
quality=100

# 生成输出目录，拷贝原目录后在副本上操作，保证原目录不被修改
timestamp=$(date +%Y%m%d_%H%M%S)
out_dir="${image_dir}_${timestamp}_resized"
cp -R "$image_dir" "$out_dir"

imageNum=0
compressNum=0

handle_file() {
  local file=$1
  if [[ "$file" == *.png || "$file" == *.jpg || "$file" == *.jpeg ]]; then
    imageNum=$((imageNum + 1))
    local width height
    width=$(sips -g pixelWidth "$file" | tail -n1 | cut -d' ' -f4)
    height=$(sips -g pixelHeight "$file" | tail -n1 | cut -d' ' -f4)
    if ((width > target_size || height > target_size)); then
      # 按较长边缩放；原脚本只按宽度，会让竖图没被缩小
      if ((width >= height)); then
        sips --resampleWidth "$target_size" "$file" >/dev/null
      else
        sips --resampleHeight "$target_size" "$file" >/dev/null
      fi
      echo "压缩了 $file"
      compressNum=$((compressNum + 1))
    fi
  elif [[ "$file" == *.webp ]]; then
    imageNum=$((imageNum + 1))
    cwebp -quiet -q "$quality" "$file" -o "$file"
    echo "压缩了 $file"
    compressNum=$((compressNum + 1))
  fi
}

traverse() {
  for file in "$1"/*; do
    if [[ -d "$file" ]]; then
      traverse "$file"
    else
      handle_file "$file"
    fi
  done
}

# 原目录大小（未变化，供对比）
start=$(du -sh "$image_dir" | cut -f1)

traverse "$out_dir"

end=$(du -sh "$out_dir" | cut -f1)

echo ""
echo "==== 本次共检索到 ${imageNum} 张图片，压缩处理了 ${compressNum} 张 ===="
echo "==== 压缩前大小: ${start}    压缩后大小: ${end} ===="
echo "==== 输出目录: ${out_dir} ===="
echo ""
