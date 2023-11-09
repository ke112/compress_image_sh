#!/bin/bash

# 定义要处理的图片文件夹路径
image_dir=$1

# 定义目标图片大小
target_size="1024" #单位为像素

# 定义压缩后的质量 (针对webp)
quality="100"

# 图片总个数
imageNum=0

# 压缩了的个数
compressNum=0

function handle_file() {
  file=$1
  if [[ "$file" == *.png || "$file" == *.jpg || "$file" == *.jpeg ]]; then
    imageNum=$(($imageNum + 1))
    # 获取原始图片宽度
    width=$(sips -g pixelWidth "$file" | tail -n1 | cut -d' ' -f4)
    # 获取原始图片高度
    height=$(sips -g pixelHeight "$file" | tail -n1 | cut -d' ' -f4)
    # 如果原始图片尺寸大于目标尺寸，调整图片大小
    if ((width > target_size || height > target_size)); then
      sips --resampleWidth "$target_size" "$file" #--resampleWidth 选项接受一个整数参数，表示将图像的宽度调整为指定的像素数。
      #当指定了宽度参数后，sips 将按比例调整图像的高度，以保持图像的纵横比不变。
      echo "压缩了 $file"
      compressNum=$(($compressNum + 1))
    fi
  elif [[ "$file" == *.webp ]]; then
    imageNum=$(($imageNum + 1))
    cwebp -quiet -q "$quality" "$file" -o "$file" #该命令的作用是将指定的图像文件转换为 WebP 格式，并设置了指定的图像质量参数
    echo "压缩了 $file"
    compressNum=$(($compressNum + 1))
  fi
}

# 定义递归遍历函数
function traverse() {
  for file in "$1"/*; do
    if [[ -d "$file" ]]; then
      traverse "$file"
    else
      handle_file
    fi
  done
}

# 显示压缩前的文件夹大小
r1=$(du -sh $image_dir)
start=$(echo $r1 | cut -d ' ' -f 1)

# 调用递归遍历函数
traverse "$image_dir"

# 显示压缩后的文件夹大小
r2=$(du -sh $image_dir)
end=$(echo $r2 | cut -d ' ' -f 1)

# 统计压缩了的个数
echo ""
echo ""
echo "==== 本次共检索到${imageNum}张图片,压缩处理了${compressNum}张 ===="
echo "==== 压缩前大小:$start         压缩后大小:$end ===="
echo ""
echo ""
