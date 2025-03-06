#!/bin/bash

# 默认配置
DEFAULT_KAFKA_PORT=9092
DEFAULT_CONTROLLER_PORT=9093
DEFAULT_KAFKA_NAME="kafka-single"
DEFAULT_KAFKA_USERNAME="root"
DEFAULT_KAFKA_PASSWORD="123456"
DEFAULT_HEAP_MEMORY="1G"      # 默认堆内存大小
DEFAULT_CONTAINER_MEMORY="2G"  # 默认容器内存限制
DEFAULT_CPU_LIMIT="2.0"       # 默认 CPU 限制（核心数）
DEFAULT_CPU_REQUEST="1.0"     # 默认 CPU 请求（核心数）

# 帮助信息
show_usage() {
    echo "用法: $0 [选项]"
    echo "选项:"
    echo "  -h, --help                显示此帮助信息"
    echo "  -p, --port PORT           设置Kafka端口号 (默认: ${DEFAULT_KAFKA_PORT})"
    echo "  -c, --controller-port PORT 设置Controller端口号 (默认: ${DEFAULT_CONTROLLER_PORT})"
    echo "  -n, --name NAME           设置服务名称 (默认: ${DEFAULT_KAFKA_NAME})"
    echo "  -u, --username USERNAME   设置Kafka用户名 (默认: ${DEFAULT_KAFKA_USERNAME})"
    echo "  -w, --password PASSWORD   设置Kafka密码 (默认: ${DEFAULT_KAFKA_PASSWORD})"
    echo "  --host-ip IP              手动指定主机IP (可选)"
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
        -p|--port)
            KAFKA_PORT="$2"
            shift 2
            ;;
        -c|--controller-port)
            CONTROLLER_PORT="$2"
            shift 2
            ;;
        -n|--name)
            KAFKA_NAME="$2"
            shift 2
            ;;
        -u|--username)
            KAFKA_USERNAME="$2"
            shift 2
            ;;
        -w|--password)
            KAFKA_PASSWORD="$2"
            shift 2
            ;;
        --host-ip)
            MANUAL_HOST_IP="$2"
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

# 设置默认值（如果未通过参数指定）
KAFKA_PORT=${KAFKA_PORT:-$DEFAULT_KAFKA_PORT}
CONTROLLER_PORT=${CONTROLLER_PORT:-$DEFAULT_CONTROLLER_PORT}
KAFKA_NAME=${KAFKA_NAME:-$DEFAULT_KAFKA_NAME}
KAFKA_USERNAME=${KAFKA_USERNAME:-$DEFAULT_KAFKA_USERNAME}
KAFKA_PASSWORD=${KAFKA_PASSWORD:-$DEFAULT_KAFKA_PASSWORD}
HEAP_MEMORY=${HEAP_MEMORY:-$DEFAULT_HEAP_MEMORY}
CONTAINER_MEMORY=${CONTAINER_MEMORY:-$DEFAULT_CONTAINER_MEMORY}
CPU_LIMIT=${CPU_LIMIT:-$DEFAULT_CPU_LIMIT}
CPU_REQUEST=${CPU_REQUEST:-$DEFAULT_CPU_REQUEST}

# 添加IP获取函数
get_host_ip() {
    # 如果手动指定了IP，直接使用
    if [ ! -z "$MANUAL_HOST_IP" ]; then
        # 验证IP格式
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
            # MacOS - 尝试多个常见网络接口
            for interface in en0 en1 en2 en3; do
                host_ip=$(ipconfig getifaddr $interface 2>/dev/null)
                if [ ! -z "$host_ip" ]; then
                    echo $host_ip
                    return 0
                fi
            done
            # 如果上面都失败了，尝试使用 ifconfig
            host_ip=$(ifconfig | grep "inet " | grep -v 127.0.0.1 | awk '{print $2}' | head -n 1)
            ;;
        Linux)
            # Linux - 尝试多种方法
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

echo "当前主机IP: $HOST_IP"
echo "Kafka端口: $KAFKA_PORT"
echo "Controller端口: $CONTROLLER_PORT"
echo "服务名称: $KAFKA_NAME"

# 创建必要的目录
mkdir -p ./${KAFKA_NAME}/{data,config}

# 设置目录权限
chmod 777 ./${KAFKA_NAME}/data
chmod 777 ./${KAFKA_NAME}/config

# 生成集群ID
CLUSTER_ID=$(od -x -N 4 /dev/urandom | head -1 | awk '{print $2}')

# 创建 JAAS 配置文件
cat > ./${KAFKA_NAME}/config/kafka_jaas.conf << EOL
KafkaServer {
    org.apache.kafka.common.security.plain.PlainLoginModule required
    username="${KAFKA_USERNAME}"
    password="${KAFKA_PASSWORD}"
    user_${KAFKA_USERNAME}="${KAFKA_PASSWORD}";
};

Client {
    org.apache.kafka.common.security.plain.PlainLoginModule required
    username="${KAFKA_USERNAME}"
    password="${KAFKA_PASSWORD}";
};
EOL

# 创建docker-compose.yml文件
cat > ./${KAFKA_NAME}/docker-compose.yml << EOL
services:
  kafka:
    image: 'bitnami/kafka:3.9.0'
    container_name: ${KAFKA_NAME}-kafka
    ports:
      - '${KAFKA_PORT}:9092'
      - '${CONTROLLER_PORT}:9093'
    environment:
      - KAFKA_CFG_NODE_ID=1
      - KAFKA_CFG_PROCESS_ROLES=controller,broker
      - KAFKA_CFG_CONTROLLER_QUORUM_VOTERS=1@kafka:9093
      - KAFKA_CFG_CONTROLLER_LISTENER_NAMES=CONTROLLER
      - KAFKA_CFG_LISTENERS=SASL_PLAINTEXT://:9092,CONTROLLER://:9093
      - KAFKA_CFG_ADVERTISED_LISTENERS=SASL_PLAINTEXT://${HOST_IP}:${KAFKA_PORT}
      - KAFKA_CFG_LISTENER_SECURITY_PROTOCOL_MAP=CONTROLLER:PLAINTEXT,SASL_PLAINTEXT:SASL_PLAINTEXT
      - KAFKA_CFG_INTER_BROKER_LISTENER_NAME=SASL_PLAINTEXT
      - KAFKA_KRAFT_CLUSTER_ID=${CLUSTER_ID}
      - KAFKA_CFG_AUTO_CREATE_TOPICS_ENABLE=true
      - KAFKA_ENABLE_KRAFT=yes
      - KAFKA_CLIENT_USERS=${KAFKA_USERNAME}
      - KAFKA_CLIENT_PASSWORDS=${KAFKA_PASSWORD}
      - KAFKA_CFG_SASL_ENABLED_MECHANISMS=PLAIN
      - KAFKA_CFG_SASL_MECHANISM_INTER_BROKER_PROTOCOL=PLAIN
      - ALLOW_PLAINTEXT_LISTENER=yes
      - KAFKA_HEAP_OPTS=-Xmx${HEAP_MEMORY} -Xms${HEAP_MEMORY}
      - KAFKA_OPTS=-Djava.security.auth.login.config=/bitnami/kafka/config/kafka_jaas.conf
    volumes:
      - ./data:/bitnami/kafka/data
      - ./config:/bitnami/kafka/config
    deploy:
      resources:
        limits:
          memory: ${CONTAINER_MEMORY}
          cpus: ${CPU_LIMIT}
        reservations:
          memory: ${HEAP_MEMORY}
          cpus: ${CPU_REQUEST}
EOL

# 启动docker compose
echo "启动docker compose..."
cd ./${KAFKA_NAME}
docker compose up -d

# 等待Kafka启动
echo "等待Kafka启动..."
max_attempts=30
attempt=1

while [ $attempt -le $max_attempts ]; do
    # 检查容器状态
    container_status=$(docker inspect -f '{{.State.Status}}' ${KAFKA_NAME}-kafka 2>/dev/null)
    
    if [ "$container_status" != "running" ]; then
        echo "等待容器启动..."
        sleep 2
        attempt=$((attempt + 1))
        if [ $attempt -gt $max_attempts ]; then
            echo "Kafka启动超时!"
            exit 1
        fi
        continue
    fi
    
    # 检查日志中是否包含启动成功的标志
    if docker logs ${KAFKA_NAME}-kafka 2>&1 | grep -q "Kafka Server started"; then
        echo "Kafka已就绪!"
        break
    fi
    
    echo "尝试 $attempt/$max_attempts ..."
    attempt=$((attempt + 1))
    if [ $attempt -gt $max_attempts ]; then
        echo "Kafka启动超时!"
        exit 1
    fi
    sleep 2
done

echo "Kafka集群已成功启动!"
echo "Kafka地址: ${HOST_IP}:${KAFKA_PORT}"

# 生成说明文档
generate_readme() {
    cat << EOT
# Kafka 单节点部署说明

## 部署信息
- 部署模式: KRaft (无需 ZooKeeper)
- Kafka 版本: 3.9.0
- 部署时间: $(date '+%Y-%m-%d %H:%M:%S')

## 连接信息
- Kafka 地址: \`${HOST_IP}:${KAFKA_PORT}\`
- Controller 地址: \`${HOST_IP}:${CONTROLLER_PORT}\`
- 认证信息:
  - 用户名: \`${KAFKA_USERNAME}\`
  - 密码: \`${KAFKA_PASSWORD}\`
  - 认证机制: SASL/PLAIN

## 客户端连接示例
### Java
\`\`\`java
Properties props = new Properties();
props.put("bootstrap.servers", "${HOST_IP}:${KAFKA_PORT}");
props.put("security.protocol", "SASL_PLAINTEXT");
props.put("sasl.mechanism", "PLAIN");
props.put("sasl.jaas.config", "org.apache.kafka.common.security.plain.PlainLoginModule required username=\\"${KAFKA_USERNAME}\\" password=\\"${KAFKA_PASSWORD}\\";");
\`\`\`

### Python (kafka-python)
\`\`\`python
from kafka import KafkaConsumer, KafkaProducer

conf = {
    'bootstrap_servers': ['${HOST_IP}:${KAFKA_PORT}'],
    'security_protocol': 'SASL_PLAINTEXT',
    'sasl_mechanism': 'PLAIN',
    'sasl_plain_username': '${KAFKA_USERNAME}',
    'sasl_plain_password': '${KAFKA_PASSWORD}'
}

producer = KafkaProducer(**conf)
consumer = KafkaConsumer('my-topic', **conf)
\`\`\`

### Spring Boot
\`\`\`yaml
spring:
  kafka:
    bootstrap-servers: ${HOST_IP}:${KAFKA_PORT}
    properties:
      security.protocol: SASL_PLAINTEXT
      sasl.mechanism: PLAIN
      sasl.jaas.config: org.apache.kafka.common.security.plain.PlainLoginModule required username="${KAFKA_USERNAME}" password="${KAFKA_PASSWORD}";
\`\`\`

### Go (Sarama)
\`\`\`go
package main

import (
    "github.com/Shopify/sarama"
    "log"
)

func main() {
    config := sarama.NewConfig()
    
    // 配置 SASL/PLAIN 认证
    config.Net.SASL.Enable = true
    config.Net.SASL.Mechanism = sarama.SASLTypePlaintext
    config.Net.SASL.User = "${KAFKA_USERNAME}"
    config.Net.SASL.Password = "${KAFKA_PASSWORD}"
    config.Net.SASL.Handshake = true
    
    // 设置安全协议
    config.Net.TLS.Enable = false
    config.Version = sarama.V3_9_0_0 // 使用与服务器相同的版本
    
    // 创建生产者
    producer, err := sarama.NewSyncProducer([]string{"${HOST_IP}:${KAFKA_PORT}"}, config)
    if err != nil {
        log.Fatalf("Failed to create producer: %s", err)
    }
    defer producer.Close()
    
    // 创建消费者
    consumer, err := sarama.NewConsumer([]string{"${HOST_IP}:${KAFKA_PORT}"}, config)
    if err != nil {
        log.Fatalf("Failed to create consumer: %s", err)
    }
    defer consumer.Close()
}

// 生产者示例
func produceMessage(producer sarama.SyncProducer) {
    msg := &sarama.ProducerMessage{
        Topic: "my-topic",
        Value: sarama.StringEncoder("test message"),
    }
    
    partition, offset, err := producer.SendMessage(msg)
    if err != nil {
        log.Printf("Failed to send message: %s", err)
        return
    }
    log.Printf("Message sent to partition %d at offset %d", partition, offset)
}

// 消费者示例
func consumeMessages(consumer sarama.Consumer) {
    // 获取指定主题的分区列表
    partitions, err := consumer.Partitions("my-topic")
    if err != nil {
        log.Printf("Failed to get partitions: %s", err)
        return
    }
    
    // 为每个分区创建消费者
    for _, partition := range partitions {
        pc, err := consumer.ConsumePartition("my-topic", partition, sarama.OffsetNewest)
        if err != nil {
            log.Printf("Failed to create partition consumer: %s", err)
            continue
        }
        defer pc.Close()
        
        // 在 goroutine 中处理消息
        go func(pc sarama.PartitionConsumer) {
            for msg := range pc.Messages() {
                log.Printf("Message received: %s", string(msg.Value))
            }
        }(pc)
    }
}
\`\`\`

## 目录结构
\`\`\`
./${KAFKA_NAME}/
├── docker-compose.yml    # Docker Compose 配置文件
├── data/                # Kafka 数据目录
└── config/             # Kafka 配置目录
\`\`\`

## 常用命令示例

### 主题管理
1. 创建主题
\`\`\`bash
docker exec ${KAFKA_NAME}-kafka kafka-topics.sh \\
  --create \\
  --topic my-topic \\
  --bootstrap-server localhost:9092 \\
  --partitions 3 \\
  --replication-factor 1 \\
  --command-config /bitnami/kafka/config/producer.properties
\`\`\`

2. 查看主题列表
\`\`\`bash
docker exec ${KAFKA_NAME}-kafka kafka-topics.sh \\
  --list \\
  --bootstrap-server localhost:9092 \\
  --command-config /bitnami/kafka/config/producer.properties
\`\`\`

3. 查看主题详情
\`\`\`bash
docker exec ${KAFKA_NAME}-kafka kafka-topics.sh \\
  --describe \\
  --topic my-topic \\
  --bootstrap-server localhost:9092 \\
  --command-config /bitnami/kafka/config/producer.properties
\`\`\`

### 消息操作
1. 生产消息
\`\`\`bash
docker exec -it ${KAFKA_NAME}-kafka kafka-console-producer.sh \\
  --topic my-topic \\
  --bootstrap-server localhost:9092 \\
  --producer.config /bitnami/kafka/config/producer.properties
\`\`\`

2. 消费消息
\`\`\`bash
docker exec -it ${KAFKA_NAME}-kafka kafka-console-consumer.sh \\
  --topic my-topic \\
  --from-beginning \\
  --bootstrap-server localhost:9092 \\
  --consumer.config /bitnami/kafka/config/consumer.properties
\`\`\`

### 服务管理
1. 停止服务
\`\`\`bash
cd ./${KAFKA_NAME} && docker compose down
\`\`\`

2. 重启服务
\`\`\`bash
cd ./${KAFKA_NAME} && docker compose restart
\`\`\`

3. 查看日志
\`\`\`bash
cd ./${KAFKA_NAME} && docker compose logs -f
\`\`\`

## 注意事项
1. 本部署使用 KRaft 模式，不需要 ZooKeeper
2. 外部客户端连接请使用 \`${HOST_IP}:${KAFKA_PORT}\`
3. 容器内部连接请使用 \`localhost:9092\`
4. 数据持久化在 \`./${KAFKA_NAME}/data\` 目录

## 常见问题
1. 如果遇到连接问题，请检查：
   - 防火墙是否开放了 ${KAFKA_PORT} 端口
   - 是否使用了正确的连接地址
2. 如果需要重置数据：
   - 停止服务：\`docker compose down\`
   - 删除数据目录：\`rm -rf data\`
   - 重新启动：\`docker compose up -d\`
## 参考资料
- [Kafka 官方文档](https://kafka.apache.org/documentation/)
- [Bitnami Kafka Docker 镜像文档](https://hub.docker.com/r/bitnami/kafka)

## 资源限制配置
### 内存配置
- JVM 堆内存: ${HEAP_MEMORY}
- 容器内存限制: ${CONTAINER_MEMORY}

### CPU 配置
- CPU 核心数上限: ${CPU_LIMIT}
- CPU 核心数下限: ${CPU_REQUEST}

要调整资源限制，可以使用以下参数：
\`\`\`bash
# 设置内存
./init.sh --heap-memory 2G --container-memory 4G

# 设置 CPU（支持小数点，如 0.5 表示半个核心）
./init.sh --cpu-limit 2 --cpu-request 1

# 同时设置内存和 CPU
./init.sh --heap-memory 2G --container-memory 4G --cpu-limit 2 --cpu-request 1
\`\`\`

注意事项：
1. 内存配置：
   - 容器内存限制（--container-memory）应该总是大于 JVM 堆内存（--heap-memory）
   - 建议容器内存限制至少比堆内存大 1GB，以给系统和其他开销留出空间

2. CPU 配置：
   - CPU 限制（--cpu-limit）定义了容器可以使用的最大 CPU 核心数
   - CPU 请求（--cpu-request）定义了容器需要的最小 CPU 核心数
   - CPU 值可以使用小数，如 0.5 表示半个核心
   - 建议 CPU 限制值至少是请求值的 1.5 倍，以处理流量突发
EOT
}

# 生成说明文档并同时输出到终端和文件
README_CONTENT=$(generate_readme)
echo "$README_CONTENT" | tee README.md

echo "=========================================================="
echo "说明文档已生成到 README.md"
echo "=========================================================="

