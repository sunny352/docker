#!/bin/bash

# 默认配置
DEFAULT_CLUSTER_NAME="kafka-cluster1"
DEFAULT_BASE_PORT=9092
DEFAULT_KAFKA_VERSION="3.9.0"
DEFAULT_BROKERS=3
DEFAULT_CONTROLLER_PORT=9093
DEFAULT_USERNAME="root"
DEFAULT_PASSWORD="123456"

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

# 生成JAAS配置文件
cat > ./${CLUSTER_NAME}/kafka_server_jaas.conf <<EOF
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
    mkdir -p ./${CLUSTER_NAME}/kafka-${i}/data
    
    cat >> ./${CLUSTER_NAME}/compose.yaml <<EOF
  kafka-${i}:
    image: apache/kafka:${KAFKA_VERSION}
    container_name: ${CLUSTER_NAME}_kafka_${i}
    ports:
      - "${NODE_PORT}:9092"
    environment:
      - CLUSTER_ID=kafka-cluster-1
      - KAFKA_NODE_ID=${i}
      - KAFKA_PROCESS_ROLES=broker,controller
      - KAFKA_CONTROLLER_QUORUM_VOTERS=$(for ((j=0;j<BROKERS;j++)); do echo -n "$j@kafka-$j:9093"; if [ $j -lt $((BROKERS-1)) ]; then echo -n ","; fi; done)
      - KAFKA_LISTENER_SECURITY_PROTOCOL_MAP=PLAINTEXT:SASL_PLAINTEXT,CONTROLLER:PLAINTEXT
      - KAFKA_CONTROLLER_LISTENER_NAMES=CONTROLLER
      - KAFKA_LISTENERS=PLAINTEXT://kafka-${i}:9092,CONTROLLER://kafka-${i}:9093
      - KAFKA_ADVERTISED_LISTENERS=PLAINTEXT://${HOST_IP}:${NODE_PORT}
      - KAFKA_INTER_BROKER_LISTENER_NAME=PLAINTEXT
      - KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR=1
      - KAFKA_GROUP_INITIAL_REBALANCE_DELAY_MS=0
      - KAFKA_SASL_ENABLED_MECHANISMS=PLAIN
      - KAFKA_SASL_MECHANISM_INTER_BROKER_PROTOCOL=PLAIN
      - KAFKA_SECURITY_INTER_BROKER_PROTOCOL=SASL_PLAINTEXT
      - KAFKA_OPTS=-Djava.security.auth.login.config=/etc/kafka/kafka_server_jaas.conf
    volumes:
      - ./kafka-${i}/data:/var/lib/kafka/data
      - ./kafka_server_jaas.conf:/etc/kafka/kafka_server_jaas.conf
    networks:
      kafka_net:
        aliases:
          - kafka-${i}

EOF
done

echo "开始部署Kafka集群..."

# 创建并启动容器
cd ${CLUSTER_NAME}
docker-compose up -d

# 等待容器启动并准备就绪
echo "正在启动 Kafka 集群（预计需要 1-2 分钟）..."
MAX_ATTEMPTS=60
INTERVAL=1
READY_COUNT=0

wait_for_kafka() {
    local container=$1
    local broker_id=$2
    local attempts=0
    
    while [ $attempts -lt $MAX_ATTEMPTS ]; do
        # 检查容器状态
        status=$(docker inspect -f '{{.State.Status}}' $container 2>/dev/null)
        if [ "$status" != "running" ]; then
            echo "错误: 容器 $container 状态为 $status"
            return 1
        fi
        
        # 检查是否包含最终的启动成功标志
        if docker logs $container 2>&1 | grep -q "Kafka Server started"; then
            # 额外等待 5 秒确保服务完全就绪
            sleep 5
            return 0
        fi
        
        attempts=$((attempts + 1))
        if [ $attempts -eq $MAX_ATTEMPTS ]; then
            echo "错误: 等待容器 $container 就绪超时"
            return 1
        fi
        
        echo -n "."
        sleep $INTERVAL
    done
}

# 检查所有容器
for ((i=0; i<BROKERS; i++)); do
    container="${CLUSTER_NAME}_kafka_${i}"
    echo -n "等待 Kafka broker ${i} 就绪"
    if wait_for_kafka $container $i; then
        echo " 就绪！"
        READY_COUNT=$((READY_COUNT + 1))
    else
        echo " 失败！"
        echo "查看详细错误信息："
        docker logs $container
        exit 1
    fi
done

# 最后验证集群整体状态
if [ $READY_COUNT -eq $BROKERS ]; then
    echo "验证集群整体状态..."
    # 等待几秒确保所有服务就绪
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

## 基本使用示例

### 创建 client.properties 文件
首先创建包含认证信息的配置文件：

\`\`\`bash
cat > client.properties <<EOF
security.protocol=SASL_PLAINTEXT
sasl.mechanism=PLAIN
sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required username="${USERNAME}" password="${PASSWORD}";
EOF
\`\`\`

### 创建 Topic
\`\`\`bash
# 创建一个包含3个分区、2个副本的 topic
docker exec ${CLUSTER_NAME}_kafka_0 kafka-topics.sh --create --topic my-topic --partitions 3 --replication-factor 2 --bootstrap-server kafka-0:9092 --command-config /etc/kafka/client.properties
\`\`\`

### 查看 Topic 列表
\`\`\`bash
docker exec ${CLUSTER_NAME}_kafka_0 kafka-topics.sh --list --bootstrap-server kafka-0:9092 --command-config /etc/kafka/client.properties
\`\`\`

### 生产消息
\`\`\`bash
# 使用控制台生产者发送消息
docker exec -it ${CLUSTER_NAME}_kafka_0 kafka-console-producer.sh --topic my-topic --bootstrap-server kafka-0:9092 --producer.config /etc/kafka/client.properties
\`\`\`

### 消费消息
\`\`\`bash
# 使用控制台消费者接收消息
docker exec -it ${CLUSTER_NAME}_kafka_0 kafka-console-consumer.sh --topic my-topic --from-beginning --bootstrap-server kafka-0:9092 --consumer.config /etc/kafka/client.properties
\`\`\`

### 查看 Topic 详情
\`\`\`bash
docker exec ${CLUSTER_NAME}_kafka_0 kafka-topics.sh --describe --topic my-topic --bootstrap-server kafka-0:9092 --command-config /etc/kafka/client.properties
\`\`\`

## 使用客户端连接
在客户端配置中使用以下配置：

\`\`\`properties
bootstrap.servers=$(for ((i=0; i<BROKERS; i++)); do echo -n "${HOST_IP}:$((BASE_PORT + i))"; if [ $i -lt $((BROKERS-1)) ]; then echo -n ","; fi; done)
security.protocol=SASL_PLAINTEXT
sasl.mechanism=PLAIN
sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required username="${USERNAME}" password="${PASSWORD}";
\`\`\`

## 管理命令
### 启动集群
\`\`\`bash
cd ${CLUSTER_NAME}
docker-compose up -d
\`\`\`

### 停止集群
\`\`\`bash
cd ${CLUSTER_NAME}
docker-compose down
\`\`\`

### 查看日志
\`\`\`bash
cd ${CLUSTER_NAME}
docker-compose logs -f
\`\`\`
EOF

    # 输出成功信息和使用说明
    echo
    echo "🎉 Kafka 集群已成功启动！"
    echo
    echo "集群信息:"
    echo "- 集群名称: ${CLUSTER_NAME}"
    echo "- Kafka 版本: ${KAFKA_VERSION}"
    echo "- Broker 数量: ${BROKERS}"
    echo "- 模式: KRaft (无需 Zookeeper)"
    echo
    echo "连接地址:"
    for ((i=0; i<BROKERS; i++)); do
        echo "- Broker ${i}: ${HOST_IP}:$((BASE_PORT + i))"
    done
    echo
    echo "快速测试:"
    echo "1. 创建测试主题:"
    echo "   docker exec ${CLUSTER_NAME}_kafka_0 kafka-topics.sh --create --topic test --partitions 3 --replication-factor 2 --bootstrap-server kafka-0:9092"
    echo
    echo "2. 发送消息:"
    echo "   docker exec -it ${CLUSTER_NAME}_kafka_0 kafka-console-producer.sh --topic test --bootstrap-server kafka-0:9092"
    echo
    echo "3. 接收消息:"
    echo "   docker exec -it ${CLUSTER_NAME}_kafka_0 kafka-console-consumer.sh --topic test --from-beginning --bootstrap-server kafka-0:9092"
    echo
    echo "详细使用说明请查看: README.md"
    echo
    echo "祝您使用愉快！"
else
    echo "错误: 只有 $READY_COUNT/$BROKERS 个 broker 成功启动"
    docker-compose logs
    exit 1
fi
