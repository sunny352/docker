#!/bin/bash

# 默认配置
DEFAULT_CLUSTER_NAME="redis-cluster1"
DEFAULT_BASE_PORT=6379
DEFAULT_REDIS_VERSION="7.2"
DEFAULT_REDIS_PASSWORD="123456"
DEFAULT_SHARDS=3
DEFAULT_REPLICAS=1

# 帮助信息
show_usage() {
    echo "用法: $0 [选项]"
    echo "选项:"
    echo "  -h, --help                显示此帮助信息"
    echo "  -n, --name NAME           设置集群名称 (默认: ${DEFAULT_CLUSTER_NAME})"
    echo "  -p, --port PORT           设置基础端口号 (默认: ${DEFAULT_BASE_PORT})"
    echo "  -v, --version VERSION     设置Redis版本 (默认: ${DEFAULT_REDIS_VERSION})"
    echo "  -w, --password PASSWORD   设置Redis密码 (默认: ${DEFAULT_REDIS_PASSWORD})"
    echo "  -s, --shards SHARDS      设置分片数量 (默认: ${DEFAULT_SHARDS})"
    echo "  -r, --replicas REPLICAS  设置每个分片的副本数 (默认: ${DEFAULT_REPLICAS})"
    echo "  --host-ip IP              手动指定主机IP (可选)"
    exit 1
}

# 参数解析
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_usage
            ;;
        -n|--name)
            CLUSTER_NAME="$2"
            shift 2
            ;;
        -p|--port)
            BASE_PORT="$2"
            shift 2
            ;;
        -v|--version)
            REDIS_VERSION="$2"
            shift 2
            ;;
        -w|--password)
            REDIS_PASSWORD="$2"
            shift 2
            ;;
        -s|--shards)
            SHARDS="$2"
            shift 2
            ;;
        -r|--replicas)
            REPLICAS="$2"
            shift 2
            ;;
        --host-ip)
            MANUAL_HOST_IP="$2"
            shift 2
            ;;
        *)
            echo "错误: 未知参数 $1"
            show_usage
            ;;
    esac
done

# 设置默认值
CLUSTER_NAME=${CLUSTER_NAME:-$DEFAULT_CLUSTER_NAME}
BASE_PORT=${BASE_PORT:-$DEFAULT_BASE_PORT}
REDIS_VERSION=${REDIS_VERSION:-$DEFAULT_REDIS_VERSION}
REDIS_PASSWORD=${REDIS_PASSWORD:-$DEFAULT_REDIS_PASSWORD}
SHARDS=${SHARDS:-$DEFAULT_SHARDS}
REPLICAS=${REPLICAS:-$DEFAULT_REPLICAS}

# 验证必要参数
if ! [[ "$BASE_PORT" =~ ^[0-9]+$ ]] || [ "$BASE_PORT" -lt 1024 ] || [ "$BASE_PORT" -gt 65535 ]; then
    echo "错误: 端口号必须是1024-65535之间的数字"
    exit 1
fi

# 计算需要的总端口数
TOTAL_NODES=$((SHARDS * (REPLICAS + 1)))
if [ $((BASE_PORT + TOTAL_NODES - 1)) -gt 65535 ]; then
    echo "错误: 基础端口号过大，无法为所有节点分配端口"
    exit 1
fi

# 检查端口占用
check_port() {
    local port=$1
    if command -v nc >/dev/null 2>&1; then
        if nc -z localhost $port >/dev/null 2>&1; then
            echo "错误: 端口 $port 已被占用"
            exit 1
        fi
    elif command -v lsof >/dev/null 2>&1; then
        if lsof -i :$port >/dev/null 2>&1; then
            echo "错误: 端口 $port 已被占用"
            exit 1
        fi
    fi
}

# 检查所需端口
for ((i=0; i<TOTAL_NODES; i++)); do
    check_port $((BASE_PORT + i))
done

# 添加IP获取函数
get_host_ip() {
    if [ ! -z "$MANUAL_HOST_IP" ]; then
        if [[ $MANUAL_HOST_IP =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            echo "$MANUAL_HOST_IP"
            return 0
        else
            echo "错误: 无效的IP地址格式: $MANUAL_HOST_IP" >&2
            exit 1
        fi
    fi

    case "$(uname -s)" in
        Darwin)
            for interface in en0 en1 en2 en3; do
                host_ip=$(ipconfig getifaddr $interface 2>/dev/null)
                if [ ! -z "$host_ip" ]; then
                    echo $host_ip
                    return 0
                fi
            done
            host_ip=$(ifconfig | grep "inet " | grep -v 127.0.0.1 | awk '{print $2}' | head -n 1)
            ;;
        Linux)
            if command -v hostname >/dev/null 2>&1; then
                host_ip=$(hostname -I | awk '{print $1}')
            fi
            
            if [ -z "$host_ip" ]; then
                host_ip=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v 127.0.0.1 | head -n 1)
            fi
            
            if [ -z "$host_ip" ]; then
                host_ip=$(ifconfig | grep "inet " | grep -v 127.0.0.1 | awk '{print $2}' | head -n 1)
            fi
            ;;
        *)
            echo "不支持的操作系统" >&2
            exit 1
            ;;
    esac

    if [ -z "$host_ip" ]; then
        echo "错误: 无法获取主机IP地址。请使用 --host-ip 参数手动指定IP地址。" >&2
        exit 1
    fi

    echo $host_ip
}

# 获取主机IP
HOST_IP=$(get_host_ip)

# 创建集群目录
mkdir -p ./${CLUSTER_NAME}

# 生成docker-compose.yml
cat > ./${CLUSTER_NAME}/compose.yaml <<EOF
networks:
  redis_cluster_net:
    driver: bridge

services:
EOF

# 生成Redis节点配置
for ((i=0; i<SHARDS; i++)); do
    # 主节点
    MASTER_PORT=$((BASE_PORT + i))
    cat >> ./${CLUSTER_NAME}/compose.yaml <<EOF
  redis-node-${i}:
    image: redis:${REDIS_VERSION}
    container_name: ${CLUSTER_NAME}_redis_${i}
    command: redis-server --port 6379
      --requirepass ${REDIS_PASSWORD}
      --masterauth ${REDIS_PASSWORD}
      --cluster-enabled yes
      --cluster-config-file nodes.conf
      --cluster-node-timeout 5000
      --appendonly yes
      --bind 0.0.0.0
      --cluster-announce-ip redis-node-${i}
      --cluster-announce-port 6379
      --cluster-announce-bus-port 16379
    ports:
      - "${MASTER_PORT}:6379"
      - "$((MASTER_PORT + 10000)):16379"
    volumes:
      - ./redis-node-${i}:/data
    networks:
      redis_cluster_net:
        aliases:
          - redis-node-${i}

EOF

    # 副本节点
    for ((j=0; j<REPLICAS; j++)); do
        REPLICA_PORT=$((BASE_PORT + i + (j+1)*SHARDS))
        cat >> ./${CLUSTER_NAME}/compose.yaml <<EOF
  redis-replica-${i}-${j}:
    image: redis:${REDIS_VERSION}
    container_name: ${CLUSTER_NAME}_redis_${i}_replica_${j}
    command: redis-server --port 6379
      --requirepass ${REDIS_PASSWORD}
      --masterauth ${REDIS_PASSWORD}
      --cluster-enabled yes
      --cluster-config-file nodes.conf
      --cluster-node-timeout 5000
      --appendonly yes
      --bind 0.0.0.0
      --cluster-announce-ip redis-replica-${i}-${j}
      --cluster-announce-port 6379
      --cluster-announce-bus-port 16379
    ports:
      - "${REPLICA_PORT}:6379"
      - "$((REPLICA_PORT + 10000)):16379"
    volumes:
      - ./redis-replica-${i}-${j}:/data
    networks:
      redis_cluster_net:
        aliases:
          - redis-replica-${i}-${j}

EOF
    done
done

echo "开始部署Redis集群..."

# 创建并启动容器
cd ${CLUSTER_NAME}
docker-compose up -d

# 等待容器启动
echo "等待容器启动..."
sleep 10

# 检查容器状态
CONTAINERS=$(docker-compose ps -q)
for container in $CONTAINERS; do
    status=$(docker inspect -f '{{.State.Status}}' $container)
    if [ "$status" != "running" ]; then
        echo "错误: 容器 $container 未正常运行，状态为: $status"
        exit 1
    fi
done

# 构建Redis集群创建命令的节点列表
echo "开始创建Redis集群..."
REDIS_NODES=""
for ((i=0; i<SHARDS; i++)); do
    REDIS_NODES="${REDIS_NODES}redis-node-${i}:6379 "
    for ((j=0; j<REPLICAS; j++)); do
        REDIS_NODES="${REDIS_NODES}redis-replica-${i}-${j}:6379 "
    done
done

# 创建集群
docker exec -it ${CLUSTER_NAME}_redis_0 redis-cli -a ${REDIS_PASSWORD} --cluster create ${REDIS_NODES} --cluster-replicas ${REPLICAS} --cluster-yes

# 验证集群状态
echo "验证集群状态..."
docker exec -it ${CLUSTER_NAME}_redis_0 redis-cli -a ${REDIS_PASSWORD} cluster info

# 验证集群连接
echo "验证集群连接..."
docker exec -it ${CLUSTER_NAME}_redis_0 redis-cli -a ${REDIS_PASSWORD} cluster nodes

# 生成集群信息和连接说明
generate_info() {
    # 构建节点列表
    local NODES=""
    for ((i=0; i<TOTAL_NODES; i++)); do
        if [ $i -gt 0 ]; then
            NODES="${NODES},"
        fi
        NODES="${NODES}${HOST_IP}:$((BASE_PORT + i))"
    done

    cat << EOF
# Redis 集群信息

## 基本信息
- 集群名称: ${CLUSTER_NAME}
- Redis版本: ${REDIS_VERSION}
- 分片数量: ${SHARDS}
- 每个分片的副本数: ${REPLICAS}
- 总节点数: ${TOTAL_NODES}
- 可用端口: ${BASE_PORT} - $((BASE_PORT + TOTAL_NODES - 1))
- Redis密码: ${REDIS_PASSWORD}

## 连接方式

### 1. 命令行连接

#### 单节点方式连接(任选其一):
$(for ((i=0; i<TOTAL_NODES; i++)); do
    echo "- \`redis-cli -h ${HOST_IP} -p $((BASE_PORT + i)) -a ${REDIS_PASSWORD}\`"
done)

#### 集群方式连接(推荐):
\`\`\`bash
redis-cli -h ${HOST_IP} -p ${BASE_PORT} -a ${REDIS_PASSWORD} -c
\`\`\`

### 2. 代码连接示例

#### Redis URL格式:
\`\`\`
redis://:${REDIS_PASSWORD}@${NODES}
\`\`\`

#### Java (Lettuce):
\`\`\`java
List<RedisURI> nodes = Arrays.asList(
$(for ((i=0; i<TOTAL_NODES; i++)); do
    echo "    RedisURI.builder().withHost(\"${HOST_IP}\").withPort($((BASE_PORT + i))).withPassword(\"${REDIS_PASSWORD}\").build()$([ $i -lt $((TOTAL_NODES-1)) ] && echo ",")"
done)
);
RedisClusterClient.create(nodes)
\`\`\`

#### Python (redis-py):
\`\`\`python
redis.RedisCluster(
    startup_nodes=[
$(for ((i=0; i<TOTAL_NODES; i++)); do
    echo "        {\"host\": \"${HOST_IP}\", \"port\": $((BASE_PORT + i))}$([ $i -lt $((TOTAL_NODES-1)) ] && echo ",")"
done)
    ],
    password="${REDIS_PASSWORD}",
    decode_responses=True
)
\`\`\`

#### Node.js (ioredis):
\`\`\`javascript
new Redis.Cluster([
$(for ((i=0; i<TOTAL_NODES; i++)); do
    echo "    {host: \"${HOST_IP}\", port: $((BASE_PORT + i))}$([ $i -lt $((TOTAL_NODES-1)) ] && echo ",")"
done)
], {
    redisOptions: {password: "${REDIS_PASSWORD}"}
})
\`\`\`

#### Go (go-redis):
\`\`\`go
redis.NewClusterClient(&redis.ClusterOptions{
    Addrs: []string{
$(for ((i=0; i<TOTAL_NODES; i++)); do
    echo "        \"${HOST_IP}:$((BASE_PORT + i))\"$([ $i -lt $((TOTAL_NODES-1)) ] && echo ",")"
done)
    },
    Password: "${REDIS_PASSWORD}",
})
\`\`\`

## 注意事项
- 使用 -c 参数启用集群模式，支持自动跳转
- 集群中的每个节点都可以用来访问整个集群
- 建议使用支持集群的客户端库来连接
- 提供所有节点地址可以提高可用性和负载均衡
- 客户端会自动处理节点的故障转移和重新分片
EOF
}

# 同时输出到终端和文件
generate_info | tee README.md
echo "集群信息已保存到 README.md"
