#!/bin/bash

# 示例服务构建脚本
# ==============
#
# 这是一个用于构建测试服务的示例脚本，用于演示滚动更新效果
# 脚本会：
#   1. 生成一个新的版本号
#   2. 通过构建参数传递版本号
#   3. 构建新的 Docker 镜像
#
# 注意：这个脚本仅用于演示目的，实际使用时应该替换为你自己的构建流程

# 确保脚本在发生错误时退出
set -e

# 配置信息
IMAGE_NAME="web-example"
IMAGE_TAG=$(date +%Y%m%d-%H%M%S)  # 使用时间戳作为tag
VERSION="v1.0.${IMAGE_TAG}"  # 使用时间戳作为版本号的一部分

# 构建镜像
echo "正在构建镜像 ${IMAGE_NAME}:${IMAGE_TAG}..."
cd web-example
docker build --build-arg VERSION=${VERSION} -t ${IMAGE_NAME}:${IMAGE_TAG} .
docker tag ${IMAGE_NAME}:${IMAGE_TAG} ${IMAGE_NAME}:latest

echo "镜像构建成功：${IMAGE_NAME}:${IMAGE_TAG} (latest)"
echo "版本号：$VERSION"