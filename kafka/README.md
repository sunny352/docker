# Kafka KRaft 集群

## 简介
该项目使用 Docker 和 Docker Compose 部署一个基于 KRaft 模式的 Kafka 集群（无需 Zookeeper）。支持自定义 broker 数量、端口和版本等配置。

## 使用说明

### 1. 克隆项目
```bash
git clone <repository-url>
cd kafka
```

### 2. 运行初始化脚本
```bash
chmod +x init.sh
./init.sh [选项]
```

### 可用的命令行选项
```
选项:
  -h, --help                显示帮助信息
  -n, --name NAME           设置集群名称 (默认: kafka-cluster1)
  -p, --port PORT           设置基础端口号 (默认: 9092)
                           将会使用连续的端口:
                           - PORT: 第一个 broker 的对外端口
                           - PORT+1: 第二个 broker 的对外端口
                           - PORT+2: 第三个 broker 的对外端口（如果配置了3个broker）
                           - 以此类推...
  -v, --version VERSION     设置 Kafka 版本 (默认: 3.9.0)
  -b, --brokers BROKERS     设置 broker 数量 (默认: 3)
  --host-ip IP             手动指定主机IP (可选)
```

### 使用示例
```bash
# 使用默认配置
./init.sh

# 指定集群名称和端口
./init.sh -n my-kafka -p 9092

# 指定 Kafka 版本和 broker 数量
./init.sh -v 3.9.0 -b 5

# 手动指定IP地址
./init.sh --host-ip 192.168.1.100

# 组合使用多个参数
./init.sh -n my-kafka -p 9092 -v 3.9.0 -b 5 --host-ip 192.168.1.100
```

### 3. 目录结构
初始化完成后，会在指定的集群名称目录下创建以下文件和目录：
```
<cluster-name>/
├── compose.yaml          # Docker Compose 配置文件
├── README.md            # 集群信息和使用说明
├── kafka-0/            # 第一个 broker 的数据目录
├── kafka-1/            # 第二个 broker 的数据目录
└── kafka-2/            # 第三个 broker 的数据目录（如果配置了3个broker）
```

### 4. 基本操作示例

#### 创建 Topic
```bash
# 创建一个包含3个分区、2个副本的 topic
docker exec <cluster-name>_kafka_0 kafka-topics.sh \
    --create \
    --topic my-topic \
    --partitions 3 \
    --replication-factor 2 \
    --bootstrap-server kafka-0:9092
```

#### 查看 Topic 列表
```bash
docker exec <cluster-name>_kafka_0 kafka-topics.sh \
    --list \
    --bootstrap-server kafka-0:9092
```

#### 生产消息
```bash
# 使用控制台生产者发送消息
docker exec -it <cluster-name>_kafka_0 kafka-console-producer.sh \
    --topic my-topic \
    --bootstrap-server kafka-0:9092
```

#### 消费消息
```bash
# 使用控制台消费者接收消息
docker exec -it <cluster-name>_kafka_0 kafka-console-consumer.sh \
    --topic my-topic \
    --from-beginning \
    --bootstrap-server kafka-0:9092
```

#### 查看 Topic 详情
```bash
docker exec <cluster-name>_kafka_0 kafka-topics.sh \
    --describe \
    --topic my-topic \
    --bootstrap-server kafka-0:9092
```

### 5. 客户端连接示例

#### Java (使用 kafka-clients)
```java
Properties props = new Properties();
props.put(ProducerConfig.BOOTSTRAP_SERVERS_CONFIG, "<host-ip>:9092,<host-ip>:9093,<host-ip>:9094");
props.put(ProducerConfig.KEY_SERIALIZER_CLASS_CONFIG, StringSerializer.class.getName());
props.put(ProducerConfig.VALUE_SERIALIZER_CLASS_CONFIG, StringSerializer.class.getName());

KafkaProducer<String, String> producer = new KafkaProducer<>(props);
```

#### Python (使用 kafka-python)
```python
from kafka import KafkaConsumer, KafkaProducer

# 生产者
producer = KafkaProducer(bootstrap_servers=['<host-ip>:9092', '<host-ip>:9093', '<host-ip>:9094'])

# 消费者
consumer = KafkaConsumer('my-topic',
                        bootstrap_servers=['<host-ip>:9092', '<host-ip>:9093', '<host-ip>:9094'],
                        auto_offset_reset='earliest',
                        enable_auto_commit=True,
                        group_id='my-group')
```

#### Node.js (使用 kafkajs)
```javascript
const { Kafka } = require('kafkajs')

const kafka = new Kafka({
  clientId: 'my-app',
  brokers: ['<host-ip>:9092', '<host-ip>:9093', '<host-ip>:9094']
})
```

#### Go (使用 Sarama)
```go
package main

import (
    "log"
    "github.com/Shopify/sarama"
)

func main() {
    // 生产者配置
    config := sarama.NewConfig()
    config.Producer.Return.Successes = true
    config.Producer.RequiredAcks = sarama.WaitForAll
    config.Producer.Retry.Max = 5

    // 连接 Kafka 集群
    brokers := []string{"<host-ip>:9092", "<host-ip>:9093", "<host-ip>:9094"}
    
    // 创建生产者
    producer, err := sarama.NewSyncProducer(brokers, config)
    if err != nil {
        log.Fatalf("Error creating producer: %v", err)
    }
    defer producer.Close()

    // 发送消息
    msg := &sarama.ProducerMessage{
        Topic: "my-topic",
        Value: sarama.StringEncoder("Hello from Go!"),
    }
    
    // 同步发送
    partition, offset, err := producer.SendMessage(msg)
    if err != nil {
        log.Printf("Failed to send message: %v", err)
    } else {
        log.Printf("Message sent to partition %d at offset %d", partition, offset)
    }

    // 创建消费者
    consumer, err := sarama.NewConsumer(brokers, nil)
    if err != nil {
        log.Fatalf("Error creating consumer: %v", err)
    }
    defer consumer.Close()

    // 获取分区消费者
    partitionConsumer, err := consumer.ConsumePartition("my-topic", 0, sarama.OffsetNewest)
    if err != nil {
        log.Fatalf("Error creating partition consumer: %v", err)
    }
    defer partitionConsumer.Close()

    // 消费消息
    for msg := range partitionConsumer.Messages() {
        log.Printf("Received message: %s", string(msg.Value))
    }
}
```

### 注意事项
1. 如果从其他机器连接，请将 `<host-ip>` 替换为服务器的实际可访问IP地址
2. 确保防火墙已开放所需端口（默认为 9092 及后续端口）
3. 可以使用以下命令检查端口是否开放：
```bash
nc -zv <host-ip> <port>
```

### 常见问题
1. 端口被占用
   - 脚本会自动检查端口占用情况
   - 如果端口被占用，可以使用 `-p` 参数指定其他起始端口

2. 无法获取主机IP
   - 脚本会自动尝试多种方法获取主机IP
   - 如果自动获取失败，可以使用 `--host-ip` 参数手动指定IP地址

3. 集群启动失败
   - 检查 Docker 日志：`docker-compose logs -f`
   - 确保分配了足够的系统资源（内存、CPU）
   - 检查端口是否被占用
   - 检查数据目录权限

### 集群管理命令

#### 启动集群
```bash
cd <cluster-name>
docker-compose up -d
```

#### 停止集群
```bash
cd <cluster-name>
docker-compose down
```

#### 查看日志
```bash
cd <cluster-name>
docker-compose logs -f
```

#### 查看集群状态
```bash
cd <cluster-name>
docker-compose ps
```

### 性能调优建议
1. 根据实际需求调整分区数和副本数
2. 合理设置消息大小和批处理参数
3. 监控并及时清理过期数据
4. 定期检查和维护磁盘空间
5. 根据业务需求调整 retention 策略
