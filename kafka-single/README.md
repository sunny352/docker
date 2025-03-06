# Kafka 单节点部署脚本

基于 Docker 的 Kafka 单节点部署脚本，支持自定义端口、用户名和密码。

## 功能特点

- 基于 KRaft 模式，无需 ZooKeeper
- 自动配置和部署 Kafka 单节点服务
- 基于 Docker 容器，易于部署和管理
- 自动检测主机 IP 和端口占用
- 支持自定义认证信息
- 提供完整的连接信息和示例代码

## 使用方法

### 1. 基本用法

```bash
./init.sh
```

这将使用默认配置创建一个 Kafka 单节点服务：
- Kafka 端口：9092
- Controller 端口：9093
- 服务名称：kafka-single
- 用户名：root
- 密码：123456

### 2. 自定义配置

```bash
./init.sh [选项]
```

可用选项：
- `-h, --help`                显示帮助信息
- `-p, --port PORT`           设置 Kafka 端口号 (默认: 9092)
- `-c, --controller-port PORT` 设置 Controller 端口号 (默认: 9093)
- `-n, --name NAME`           设置服务名称 (默认: kafka-single)
- `-u, --username USERNAME`   设置 Kafka 用户名 (默认: root)
- `-w, --password PASSWORD`   设置 Kafka 密码 (默认: 123456)
- `--host-ip IP`             手动指定主机 IP (可选)

### 3. 示例

使用自定义端口和服务名称：
```bash
./init.sh -p 9094 -c 9095 -n my-kafka
```

使用自定义用户名和密码：
```bash
./init.sh -u admin -w mypassword
```

## 端口说明

- Kafka 服务需要两个端口：
  - Kafka 服务端口：用于客户端连接（默认 9092）
  - Controller 端口：用于 KRaft 控制器（默认 9093）

## 目录结构

部署完成后会创建如下目录结构：
```
kafka-single/
├── docker-compose.yml     # Docker Compose 配置文件
├── README.md             # 服务信息和连接说明
├── kafka-data/           # Kafka 数据目录
└── kafka-config/         # Kafka 配置目录
    └── kafka_jaas.conf   # JAAS 认证配置文件
```

## 注意事项

1. 确保系统已安装 Docker 和 Docker Compose
2. 所需端口未被占用
3. 主机防火墙允许相关端口访问
4. 建议在生产环境中修改默认用户名和密码
5. 部署完成后会自动生成详细的连接信息到 README.md 文件

## 故障排除

1. 如果端口被占用：
   - 使用 `-p` 和 `-c` 参数指定其他可用端口
   - 或先停止占用端口的服务

2. 如果无法获取主机 IP：
   - 使用 `--host-ip` 参数手动指定 IP
   - 检查网络接口配置

3. 如果容器启动失败：
   - 检查 Docker 服务状态
   - 查看容器日志：`docker logs 容器名称`
   - 确保端口未被占用

4. 如果认证失败：
   - 检查用户名和密码配置是否正确
   - 确认客户端配置了正确的 SASL 认证信息

## 安全说明

1. 默认启用 SASL/PLAIN 认证
2. 所有连接都需要提供用户名和密码
3. 建议在生产环境中：
   - 使用强密码
   - 配置防火墙规则
   - 考虑启用 SSL/TLS 加密
