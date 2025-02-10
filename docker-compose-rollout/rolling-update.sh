#!/bin/bash

# Docker Compose 服务滚动更新脚本
# ===============================
#
# 这是一个通用的基于 Docker Compose 的服务滚动更新脚本，可用于任何配置了健康检查的服务。
# 脚本会自动处理以下流程：
#   1. 逐个替换现有容器
#   2. 确保新容器健康后再移除旧容器
#   3. 出现异常时自动回滚
#
# 使用要求：
#   - 目标服务必须在 docker-compose.yml 中定义
#   - 服务的镜像必须配置了 HEALTHCHECK
#   - Docker Compose 需要支持 scale 功能
#
# 使用方法：
#   ./rolling-update.sh <服务名称>
#
# 示例：
#   ./rolling-update.sh myapp

# 确保脚本在发生错误时退出
set -e

# 检查必要的参数
if [ -z "$1" ]; then
    echo "用法: $0 <服务名称>"
    echo "示例: $0 web-example"
    echo "注意: 目标服务必须在 docker-compose.yml 中定义，且配置了健康检查"
    exit 1
fi

SERVICE_NAME=$1

# 健康检查函数
check_container_health() {
    local container_id=$1
    local max_attempts=30
    local attempt=1
    local wait_time=2

    while [ $attempt -le $max_attempts ]; do
        # 检查容器是否存在
        if ! docker inspect $container_id >/dev/null 2>&1; then
            echo "错误：容器 $container_id 不存在"
            return 1
        fi

        # 检查容器健康状态
        local health_status=$(docker inspect --format='{{.State.Health.Status}}' $container_id)
        
        case "$health_status" in
            "healthy")
                echo "容器 $container_id 健康状态正常"
                return 0
                ;;
            "unhealthy")
                echo "容器 $container_id 健康检查失败"
                return 1
                ;;
            "starting")
                echo "等待容器健康状态... 第 $attempt 次检查"
                ;;
            *)
                echo "警告：容器 $container_id 状态未知 ($health_status)"
                ;;
        esac

        sleep $wait_time
        attempt=$((attempt + 1))
    done

    echo "健康检查超时: 容器未能在规定时间内变为健康状态"
    return 1
}

# 获取服务的容器数量
REPLICAS=$(docker compose ps -q $SERVICE_NAME | wc -l)

if [ $REPLICAS -eq 0 ]; then
    echo "错误：服务 $SERVICE_NAME 未运行"
    exit 1
fi

echo "服务 $SERVICE_NAME 当前副本数量: $REPLICAS"

# 逐个更新容器
for (( i=1; i<=$REPLICAS; i++ ))
do
    echo "正在更新第 $i 个容器，共 $REPLICAS 个"
    
    # 扩展服务，添加一个新容器（docker compose 会创建新容器）
    docker compose up -d --scale $SERVICE_NAME=$((REPLICAS + 1)) --no-recreate $SERVICE_NAME

    # 获取最新创建的容器ID（由于 docker compose ps 按创建时间排序，最后一个就是最新的）
    NEW_CONTAINER=$(docker compose ps -q $SERVICE_NAME | tail -n 1)
    
    # 等待新容器健康检查通过
    if ! check_container_health $NEW_CONTAINER; then
        echo "错误：新容器健康检查未通过，执行回滚"
        docker compose up -d --scale $SERVICE_NAME=$REPLICAS --no-recreate $SERVICE_NAME
        exit 1
    fi
    
    # 获取最旧的容器ID
    OLD_CONTAINER=$(docker compose ps -q $SERVICE_NAME | head -n 1)
    
    # 停止并移除最旧的容器
    echo "停止并移除最旧的容器: $OLD_CONTAINER"
    docker stop $OLD_CONTAINER
    docker rm -f $OLD_CONTAINER
    
    # 因为已经手动移除了一个容器，所以需要更新当前的副本数
    docker compose up -d --scale $SERVICE_NAME=$REPLICAS --no-recreate $SERVICE_NAME
    
    echo "第 $i 个容器更新成功"
done

echo "服务 $SERVICE_NAME 的滚动更新已完成"