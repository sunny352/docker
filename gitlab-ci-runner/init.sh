#!/bin/bash

# 预设 GitLab Runner 配置信息
GITLAB_URL="https://gitlab.com/"
REGISTRATION_TOKEN="YOUR_REGISTRATION_TOKEN"
RUNNER_DESCRIPTION="docker-runner"
RUNNER_TAGS="docker"

# 创建必要的目录
mkdir -p ./gitlab-runner/config

# 创建 docker-compose 配置文件
cat > ./docker-compose.yml << 'EOF'
version: '3.7'
services:
  gitlab-runner:
    image: gitlab/gitlab-runner:latest
    container_name: gitlab-runner
    restart: always
    volumes:
      - ./gitlab-runner/config:/etc/gitlab-runner
      - /var/run/docker.sock:/var/run/docker.sock
EOF

# 启动 GitLab Runner
docker compose up -d

# 检测容器是否就绪
max_attempts=30
attempt=1
echo "等待 GitLab Runner 容器就绪..."

while [ $attempt -le $max_attempts ]; do
    if docker compose ps gitlab-runner | grep -q "Up"; then
        echo "GitLab Runner 容器已就绪!"
        break
    fi
    echo "等待中... ($attempt/$max_attempts)"
    attempt=$((attempt + 1))
    sleep 2
done

if [ $attempt -gt $max_attempts ]; then
    echo "错误: GitLab Runner 容器启动超时"
    exit 1
fi

# 注册 Runner
docker compose exec gitlab-runner gitlab-runner register \
  --non-interactive \
  --url "$GITLAB_URL" \
  --registration-token "$REGISTRATION_TOKEN" \
  --description "$RUNNER_DESCRIPTION" \
  --tag-list "$RUNNER_TAGS" \
  --executor "docker" \
  --docker-image alpine:latest \
  --docker-volumes /var/run/docker.sock:/var/run/docker.sock

echo "GitLab Runner 安装和注册完成！"
