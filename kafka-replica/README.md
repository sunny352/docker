# Kafka KRaft 集群

## 简介
该项目使用 Docker 和 Docker Compose 部署一个基于 KRaft 模式的 Kafka 集群（无需 Zookeeper）。支持自定义 broker 数量、端口和版本等配置，并默认启用 SASL/PLAIN 认证。

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
  -u, --username USERNAME   设置SASL用户名 (默认: root)
  -w, --password PASSWORD   设置SASL密码 (默认: 123456)
  --heap-memory SIZE       设置JVM堆内存大小 (默认: 512M)
  --container-memory SIZE  设置容器内存限制 (默认: 1G)
  --cpu-limit CORES       设置CPU核心数上限 (默认: 1.0)
  --cpu-request CORES     设置CPU核心数下限 (默认: 0.5)
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

# 指定认证信息
./init.sh -u admin -w secret123

# 指定资源限制
./init.sh --heap-memory 1G --container-memory 2G --cpu-limit 2.0 --cpu-request 1.0

# 组合使用多个参数
./init.sh -n my-kafka -p 9092 -v 3.9.0 -b 5 --host-ip 192.168.1.100 -u admin -w secret123
```

### 3. 目录结构
初始化完成后，会在指定的集群名称目录下创建以下文件和目录：
```
<cluster-name>/
├── compose.yaml          # Docker Compose 配置文件
├── README.md            # 集群信息和使用说明
├── kafka_jaas.conf     # SASL 认证配置文件
├── client.properties   # 客户端配置文件
├── kafka-0/            # 第一个 broker 的数据和配置目录
│   ├── data/          # 数据目录
│   └── config/        # 配置目录
├── kafka-1/            # 第二个 broker 的数据和配置目录
└── kafka-2/            # 第三个 broker 的数据和配置目录（如果配置了3个broker）
```

### 4. 客户端配置
集群默认启用了 SASL/PLAIN 认证。客户端连接时需要使用以下配置：

```properties
bootstrap.servers=<host-ip>:9092,<host-ip>:9093,<host-ip>:9094
security.protocol=SASL_PLAINTEXT
sasl.mechanism=PLAIN
sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required username="root" password="123456";
```

注意：请根据实际设置的用户名和密码修改上述配置。

### 5. 常用命令示例

#### 创建主题
```bash
docker exec <cluster-name>_kafka_0 kafka-topics.sh \
    --create \
    --topic test \
    --partitions 3 \
    --replication-factor 2 \
    --bootstrap-server localhost:9092 \
    --command-config /bitnami/kafka/config/client.properties
```

#### 查看主题列表
```bash
docker exec <cluster-name>_kafka_0 kafka-topics.sh \
    --list \
    --bootstrap-server localhost:9092 \
    --command-config /bitnami/kafka/config/client.properties
```

#### 查看主题详情
```bash
docker exec <cluster-name>_kafka_0 kafka-topics.sh \
    --describe \
    --topic test \
    --bootstrap-server localhost:9092 \
    --command-config /bitnami/kafka/config/client.properties
```

#### 生产消息
```bash
docker exec -it <cluster-name>_kafka_0 kafka-console-producer.sh \
    --topic test \
    --bootstrap-server localhost:9092 \
    --producer.config /bitnami/kafka/config/client.properties
```

#### 消费消息
```bash
docker exec -it <cluster-name>_kafka_0 kafka-console-consumer.sh \
    --topic test \
    --from-beginning \
    --bootstrap-server localhost:9092 \
    --consumer.config /bitnami/kafka/config/client.properties
```

### 6. 集群管理

#### 启动集群
```bash
cd <cluster-name>
docker compose up -d
```

#### 停止集群
```bash
cd <cluster-name>
docker compose down
```

#### 查看日志
```bash
cd <cluster-name>
docker compose logs -f
```

### 注意事项
1. 如果从其他机器连接，请将 `<host-ip>` 替换为服务器的实际可访问IP地址
2. 确保防火墙已开放所需端口（默认为 9092 及后续端口）
3. 所有客户端连接都需要配置正确的 SASL 认证信息
4. 建议根据实际需求调整内存和CPU限制

### 常见问题
1. 端口被占用
   - 脚本会自动检查端口占用情况
   - 如果端口被占用，可以使用 `-p` 参数指定其他起始端口

2. 无法获取主机IP
   - 脚本会自动尝试多种方法获取主机IP
   - 如果自动获取失败，可以使用 `--host-ip` 参数手动指定IP地址

3. 认证失败
   - 检查客户端配置中的用户名和密码是否正确
   - 确保使用了正确的 SASL 配置

4. 集群启动失败
   - 检查 Docker 日志：`docker compose logs -f`
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
