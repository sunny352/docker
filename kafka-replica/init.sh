#!/bin/bash

# 默认配置
DEFAULT_CLUSTER_NAME="kafka-cluster1"
DEFAULT_BASE_PORT=9092
DEFAULT_KAFKA_VERSION="3.9.0"
DEFAULT_BROKERS=3
DEFAULT_CONTROLLER_PORT=9093
DEFAULT_USERNAME="root"
DEFAULT_PASSWORD="123456"
DEFAULT_HEAP_MEMORY="512M"      # 默认堆内存大小
DEFAULT_CONTAINER_MEMORY="1G"   # 默认容器内存限制
DEFAULT_CPU_LIMIT="1.0"        # 默认 CPU 限制（核心数）
DEFAULT_CPU_REQUEST="0.5"      # 默认 CPU 请求（核心数）

# 帮助信息
show_usage() {
    echo "用法: $0 [选项]"
    echo "选项:"
    echo "  -h, --help                显示此帮助信息"
    echo "  -n, --name NAME           设置集群名称 (默认: ${DEFAULT_CLUSTER_NAME})"
    echo "  -p, --port PORT           设置基础端口号 (默认: ${DEFAULT_BASE_PORT})"
    echo "  -v, --version VERSION     设置Kafka版本 (默认: ${DEFAULT_KAFKA_VERSION})"
    echo "  -b, --brokers BROKERS     设置broker数量 (默认: ${DEFAULT_BROKERS})"
    echo "  --host-ip IP              手动指定主机IP (可选)"
    echo "  -u, --username USERNAME   设置SASL用户名 (默认: ${DEFAULT_USERNAME})"
    echo "  -w, --password PASSWORD   设置SASL密码 (默认: ${DEFAULT_PASSWORD})"
    echo "  --heap-memory SIZE        设置JVM堆内存大小 (默认: ${DEFAULT_HEAP_MEMORY})"
    echo "  --container-memory SIZE   设置容器内存限制 (默认: ${DEFAULT_CONTAINER_MEMORY})"
    echo "  --cpu-limit CORES         设置CPU核心数上限 (默认: ${DEFAULT_CPU_LIMIT})"
    echo "  --cpu-request CORES       设置CPU核心数下限 (默认: ${DEFAULT_CPU_REQUEST})"
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
            KAFKA_VERSION="$2"
            shift 2
            ;;
        -b|--brokers)
            BROKERS="$2"
            shift 2
            ;;
        --host-ip)
            MANUAL_HOST_IP="$2"
            shift 2
            ;;
        -u|--username)
            USERNAME="$2"
            shift 2
            ;;
        -w|--password)
            PASSWORD="$2"
            shift 2
            ;;
        --heap-memory)
            HEAP_MEMORY="$2"
            shift 2
            ;;
        --container-memory)
            CONTAINER_MEMORY="$2"
            shift 2
            ;;
        --cpu-limit)
            CPU_LIMIT="$2"
            shift 2
            ;;
        --cpu-request)
            CPU_REQUEST="$2"
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
KAFKA_VERSION=${KAFKA_VERSION:-$DEFAULT_KAFKA_VERSION}
BROKERS=${BROKERS:-$DEFAULT_BROKERS}
USERNAME=${USERNAME:-$DEFAULT_USERNAME}
PASSWORD=${PASSWORD:-$DEFAULT_PASSWORD}
HEAP_MEMORY=${HEAP_MEMORY:-$DEFAULT_HEAP_MEMORY}
CONTAINER_MEMORY=${CONTAINER_MEMORY:-$DEFAULT_CONTAINER_MEMORY}
CPU_LIMIT=${CPU_LIMIT:-$DEFAULT_CPU_LIMIT}
CPU_REQUEST=${CPU_REQUEST:-$DEFAULT_CPU_REQUEST}

# 验证必要参数
if ! [[ "$BASE_PORT" =~ ^[0-9]+$ ]] || [ "$BASE_PORT" -lt 1024 ] || [ "$BASE_PORT" -gt 65535 ]; then
    echo "错误: 端口号必须是1024-65535之间的数字"
    exit 1
fi

# 检查端口占用
check_port() {
    local port=$1
    if command -v nc >/dev/null 2>&1; then
        if nc -z 0.0.0.0 $port >/dev/null 2>&1; then
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
echo "检查端口占用情况..."
for ((i=0; i<BROKERS; i++)); do
    # 只检查外部访问端口
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

# 生成集群ID
CLUSTER_ID=$(od -x -N 4 /dev/urandom | head -1 | awk '{print $2}')

# 生成JAAS配置文件
cat > ./${CLUSTER_NAME}/kafka_jaas.conf <<EOF
KafkaServer {
    org.apache.kafka.common.security.plain.PlainLoginModule required
    username="${USERNAME}"
    password="${PASSWORD}"
    user_${USERNAME}="${PASSWORD}";
};

Client {
    org.apache.kafka.common.security.plain.PlainLoginModule required
    username="${USERNAME}"
    password="${PASSWORD}";
};
EOF

# 创建客户端配置文件
cat > ./${CLUSTER_NAME}/client.properties <<EOF
security.protocol=SASL_PLAINTEXT
sasl.mechanism=PLAIN
sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required username="${USERNAME}" password="${PASSWORD}";
EOF

# 生成docker-compose.yml
cat > ./${CLUSTER_NAME}/compose.yaml <<EOF
networks:
  kafka_net:
    driver: bridge

services:
EOF

# 生成Kafka节点配置
for ((i=0; i<BROKERS; i++)); do
    NODE_PORT=$((BASE_PORT + i))
    
    # 创建数据目录
    mkdir -p ./${CLUSTER_NAME}/kafka-${i}/{data,config}
    chmod 777 ./${CLUSTER_NAME}/kafka-${i}/data
    chmod 777 ./${CLUSTER_NAME}/kafka-${i}/config
    cp ./${CLUSTER_NAME}/kafka_jaas.conf ./${CLUSTER_NAME}/kafka-${i}/config/
    cp ./${CLUSTER_NAME}/client.properties ./${CLUSTER_NAME}/kafka-${i}/config/
    
    cat >> ./${CLUSTER_NAME}/compose.yaml <<EOF
  kafka-${i}:
    image: bitnami/kafka:${KAFKA_VERSION}
    container_name: ${CLUSTER_NAME}_kafka_${i}
    ports:
      - "${NODE_PORT}:9092"
    environment:
      - KAFKA_CFG_NODE_ID=${i}
      - KAFKA_CFG_PROCESS_ROLES=controller,broker
      - KAFKA_CFG_CONTROLLER_QUORUM_VOTERS=$(for ((j=0;j<BROKERS;j++)); do echo -n "$j@kafka-$j:9093"; if [ $j -lt $((BROKERS-1)) ]; then echo -n ","; fi; done)
      - KAFKA_CFG_CONTROLLER_LISTENER_NAMES=CONTROLLER
      - KAFKA_CFG_LISTENERS=SASL_PLAINTEXT://:9092,CONTROLLER://:9093
      - KAFKA_CFG_ADVERTISED_LISTENERS=SASL_PLAINTEXT://${HOST_IP}:${NODE_PORT}
      - KAFKA_CFG_LISTENER_SECURITY_PROTOCOL_MAP=CONTROLLER:PLAINTEXT,SASL_PLAINTEXT:SASL_PLAINTEXT
      - KAFKA_CFG_INTER_BROKER_LISTENER_NAME=SASL_PLAINTEXT
      - KAFKA_KRAFT_CLUSTER_ID=${CLUSTER_ID}
      - KAFKA_CFG_AUTO_CREATE_TOPICS_ENABLE=true
      - KAFKA_ENABLE_KRAFT=yes
      - KAFKA_CLIENT_USERS=${USERNAME}
      - KAFKA_CLIENT_PASSWORDS=${PASSWORD}
      - KAFKA_CFG_SASL_ENABLED_MECHANISMS=PLAIN
      - KAFKA_CFG_SASL_MECHANISM_INTER_BROKER_PROTOCOL=PLAIN
      - ALLOW_PLAINTEXT_LISTENER=yes
      - KAFKA_HEAP_OPTS=-Xmx${HEAP_MEMORY} -Xms${HEAP_MEMORY}
      - KAFKA_OPTS=-Djava.security.auth.login.config=/bitnami/kafka/config/kafka_jaas.conf
    volumes:
      - ./kafka-${i}/data:/bitnami/kafka/data
      - ./kafka-${i}/config:/bitnami/kafka/config
    networks:
      kafka_net:
        aliases:
          - kafka-${i}
    deploy:
      resources:
        limits:
          memory: ${CONTAINER_MEMORY}
          cpus: ${CPU_LIMIT}
        reservations:
          memory: ${HEAP_MEMORY}
          cpus: ${CPU_REQUEST}

EOF
done

echo "开始部署Kafka集群..."

# 创建并启动容器
cd ${CLUSTER_NAME}
docker compose up -d

# 等待容器启动并准备就绪
echo "正在启动 Kafka 集群（预计需要 1-2 分钟）..."
max_attempts=30
attempt=1
READY_COUNT=0

for ((i=0; i<BROKERS; i++)); do
    container="${CLUSTER_NAME}_kafka_${i}"
    echo -n "等待 Kafka broker ${i} 就绪"
    
    while [ $attempt -le $max_attempts ]; do
        # 检查容器状态
        container_status=$(docker inspect -f '{{.State.Status}}' $container 2>/dev/null)
        
        if [ "$container_status" != "running" ]; then
            echo -n "."
            sleep 2
            attempt=$((attempt + 1))
            if [ $attempt -gt $max_attempts ]; then
                echo "\nKafka broker ${i} 启动超时!"
                docker logs $container
                exit 1
            fi
            continue
        fi
        
        # 检查是否包含最终的启动成功标志
        if docker logs $container 2>&1 | grep -q "Kafka Server started"; then
            echo " 就绪！"
            READY_COUNT=$((READY_COUNT + 1))
            break
        fi
        
        echo -n "."
        sleep 2
        attempt=$((attempt + 1))
        if [ $attempt -gt $max_attempts ]; then
            echo "\nKafka broker ${i} 启动超时!"
            docker logs $container
            exit 1
        fi
    done
    
    attempt=1
done

# 最后验证集群整体状态
if [ $READY_COUNT -eq $BROKERS ]; then
    echo "验证集群整体状态..."
    sleep 5
    
    # 生成使用说明文件
    cat > README.md <<EOF
# Kafka 集群使用说明

## 集群信息
- 集群名称: ${CLUSTER_NAME}
- Kafka 版本: ${KAFKA_VERSION}
- Broker 数量: ${BROKERS}
- 认证信息：
  - 用户名：${USERNAME}
  - 密码：${PASSWORD}
- 使用 KRaft 模式（无需 Zookeeper）

## 连接地址
$(for ((i=0; i<BROKERS; i++)); do
echo "- Broker ${i}: ${HOST_IP}:$((BASE_PORT + i))"
done)

## 客户端配置
\`\`\`properties
bootstrap.servers=$(for ((i=0; i<BROKERS; i++)); do echo -n "${HOST_IP}:$((BASE_PORT + i))"; if [ $i -lt $((BROKERS-1)) ]; then echo -n ","; fi; done)
security.protocol=SASL_PLAINTEXT
sasl.mechanism=PLAIN
sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required username="${USERNAME}" password="${PASSWORD}";
\`\`\`

## 常用命令示例

### 创建主题
\`\`\`bash
docker exec ${CLUSTER_NAME}_kafka_0 kafka-topics.sh --create --topic test --partitions 3 --replication-factor 2 --bootstrap-server localhost:9092 --command-config /bitnami/kafka/config/client.properties
\`\`\`

### 查看主题列表
\`\`\`bash
docker exec ${CLUSTER_NAME}_kafka_0 kafka-topics.sh --list --bootstrap-server localhost:9092 --command-config /bitnami/kafka/config/client.properties
\`\`\`

### 查看主题详情
\`\`\`bash
docker exec ${CLUSTER_NAME}_kafka_0 kafka-topics.sh --describe --topic test --bootstrap-server localhost:9092 --command-config /bitnami/kafka/config/client.properties
\`\`\`

### 生产消息
\`\`\`bash
docker exec -it ${CLUSTER_NAME}_kafka_0 kafka-console-producer.sh --topic test --bootstrap-server localhost:9092 --producer.config /bitnami/kafka/config/client.properties
\`\`\`

### 消费消息
\`\`\`bash
docker exec -it ${CLUSTER_NAME}_kafka_0 kafka-console-consumer.sh --topic test --from-beginning --bootstrap-server localhost:9092 --consumer.config /bitnami/kafka/config/client.properties
\`\`\`

## 集群管理

### 启动集群
\`\`\`bash
cd ${CLUSTER_NAME}
docker compose up -d
\`\`\`

### 停止集群
\`\`\`bash
cd ${CLUSTER_NAME}
docker compose down
\`\`\`

### 查看日志
\`\`\`bash
cd ${CLUSTER_NAME}
docker compose logs -f
\`\`\`
EOF

    echo
    echo "🎉 Kafka 集群已成功启动！"
    echo
    echo "集群信息:"
    echo "- 集群名称: ${CLUSTER_NAME}"
    echo "- Kafka 版本: ${KAFKA_VERSION}"
    echo "- Broker 数量: ${BROKERS}"
    echo "- 认证信息: ${USERNAME}/${PASSWORD}"
    echo
    echo "连接地址:"
    for ((i=0; i<BROKERS; i++)); do
        echo "- Broker ${i}: ${HOST_IP}:$((BASE_PORT + i))"
    done
    echo
    echo "使用说明请查看: README.md"
else
    echo "错误: 只有 $READY_COUNT/$BROKERS 个 broker 成功启动"
    docker compose logs
    exit 1
fi
