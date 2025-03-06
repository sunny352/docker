# MongoDB分片副本集集群

## 架构说明
该项目使用 Docker 和 Docker Compose 部署一个完整的 MongoDB 分片副本集集群，包括：

1. **Mongos 路由服务**
   - 负责路由客户端请求到适当的分片
   - 提供统一的访问入口
   - 实现透明的分片访问

2. **Config Server**
   - 存储集群的元数据和配置信息
   - 以副本集模式运行
   - 管理分片的数据分布

3. **Shard 服务器**
   - Shard1 和 Shard2 两个分片服务器
   - 每个分片以副本集模式运行
   - 存储实际的数据

4. **安全特性**
   - 启用认证机制（SCRAM-SHA-1）
   - 使用 keyFile 进行内部认证
   - 支持用户名密码访问控制

## 系统要求
- Docker Engine 20.10.0+
- Docker Compose v2.0.0+
- 至少 4GB 可用内存
- 至少 10GB 可用磁盘空间
- 支持的操作系统：
  - Linux（推荐）
  - macOS
  - Windows（需要 WSL2）

## 使用说明

### 1. 克隆项目
```bash
git clone <repository-url>
cd mongo-shard-replica
```

### 2. 运行初始化脚本

#### 准备工作
1. 确保 Docker 和 Docker Compose 已正确安装：
```bash
docker --version
docker compose version
```

2. 确保当前用户有足够权限：
```bash
# 如果不在 docker 组，添加当前用户到 docker 组
sudo usermod -aG docker $USER
# 重新登录以使权限生效
```

3. 确保目标端口未被占用：
```bash
# 检查默认端口
nc -zv localhost 27017-27020 2>&1
```

#### 运行脚本
```bash
chmod +x init.sh
./init.sh [选项]
```

### 可用的命令行选项
```
选项:
  -h, --help                显示帮助信息
  -n, --name NAME           设置集群名称 (默认: mongo-cluster1)
  -p, --port PORT           设置基础端口号 (默认: 27017)
                           将会使用连续的4个端口:
                           - PORT:   mongos路由服务
                           - PORT+1: config配置服务
                           - PORT+2: shard1分片服务
                           - PORT+3: shard2分片服务
  -v, --version VERSION     设置MongoDB版本 (默认: 5.0)
  -u, --username USERNAME   设置MongoDB用户名 (默认: root)
  -w, --password PASSWORD   设置MongoDB密码 (默认: 123456)
  --host-ip IP             手动指定主机IP (可选)
```

### 使用示例
```bash
# 使用默认配置
sudo ./init.sh

# 指定集群名称和端口
sudo ./init.sh -n my-cluster -p 27020

# 指定MongoDB版本和认证信息
sudo ./init.sh -v 6.0 -u admin -w mypassword

# 手动指定IP地址
sudo ./init.sh --host-ip 192.168.1.100

# 组合使用多个参数
sudo ./init.sh -n my-cluster -p 27020 -v 6.0 -u admin -w mypassword --host-ip 192.168.1.100
```

### 3. 查看集群连接信息

#### 自动生成的信息
脚本执行完成后会自动生成以下内容：

1. **终端输出**
   - 集群初始化过程的详细日志
   - 连接信息和示例命令
   - 可能的错误和解决方案

2. **README.md 文件**
   - 完整的集群配置信息
   - 多语言连接示例
   - 管理指南和最佳实践

3. **配置文件**
   - Docker Compose 配置
   - MongoDB 密钥文件
   - 各服务的数据目录

生成的连接信息包括：

1. mongosh命令行连接串（带认证机制）：
```bash
mongodb://<username>:<password>@<host-ip>:<port>/admin?authSource=admin&authMechanism=SCRAM-SHA-1
```

2. MongoDB Compass连接串（带高可用配置）：
```bash
mongodb://<username>:<password>@<host-ip>:<port>/admin?authSource=admin&authMechanism=SCRAM-SHA-1&readPreference=primary&retryWrites=true&w=majority
```

3. 应用程序连接串（带完整参数）：
```bash
mongodb://<username>:<password>@<host-ip>:<port>/admin?authSource=admin&authMechanism=SCRAM-SHA-1&readPreference=primary&retryWrites=true&w=majority&maxPoolSize=50&minPoolSize=10&maxIdleTimeMS=30000&connectTimeoutMS=10000&serverSelectionTimeoutMS=5000&socketTimeoutMS=45000&waitQueueTimeoutMS=5000&heartbeatFrequencyMS=10000
```

### 4. 目录结构
初始化完成后的完整目录结构：
```
<cluster-name>/
├── compose.yaml          # Docker Compose 配置文件
├── mongodb.key          # MongoDB 认证密钥文件（权限：400）
├── README.md           # 集群信息和使用说明
├── configsvr/          # Config Server 数据目录
│   └── ...            # Config Server 数据文件
├── shard1/            # Shard1 数据目录
│   └── ...           # Shard1 数据文件
└── shard2/            # Shard2 数据目录
    └── ...           # Shard2 数据文件
```

### 5. 资源配置说明
脚本为各服务配置了以下资源限制：

1. **Mongos 路由器**
   - CPU: 0.5 核心（最小：0.2）
   - 内存: 1GB（最小：512MB）

2. **Config Server**
   - CPU: 0.5 核心（最小：0.2）
   - 内存: 1GB（最小：512MB）

3. **分片服务器**
   - CPU: 1 核心（最小：0.5）
   - 内存: 2GB（最小：1GB）

### 6. 安全配置
1. **认证机制**
   - 使用 SCRAM-SHA-1 认证
   - keyFile 用于内部认证
   - 强制启用授权验证

2. **网络安全**
   - 使用 Docker 网络隔离
   - 仅必要端口对外暴露
   - 支持 TLS/SSL 配置（可选）

3. **访问控制**
   - 创建管理员用户
   - 角色基础访问控制
   - 支持细粒度权限配置

### 常见问题

#### 1. 端口被占用
- **症状**：启动失败，提示端口已被使用
- **解决方案**：
  ```bash
  # 查看端口占用
  sudo lsof -i :<port>
  # 使用其他端口启动
  ./init.sh -p <alternative-port>
  ```

#### 2. 无法获取主机IP
- **症状**：自动IP检测失败
- **解决方案**：
  ```bash
  # 手动查看IP
  ifconfig | grep "inet "
  # 指定IP启动
  ./init.sh --host-ip <your-ip>
  ```

#### 3. 权限问题
- **症状**：mongodb.key 权限设置失败
- **解决方案**：
  ```bash
  # 检查文件权限
  ls -l mongodb.key
  # 正确设置权限
  sudo chmod 400 mongodb.key
  sudo chown 999:999 mongodb.key
  ```

#### 4. 内存不足
- **症状**：容器启动失败或不稳定
- **解决方案**：
  - 增加系统可用内存
  - 调整容器内存限制：
    ```bash
    # 编辑 compose.yaml
    # 修改 deploy.resources.limits.memory 值
    ```

#### 5. 数据持久化
- **症状**：重启后数据丢失
- **解决方案**：
  - 确保数据目录正确挂载
  - 检查目录权限：
    ```bash
    sudo chown -R 999:999 configsvr/ shard1/ shard2/
    ```

### 性能优化建议

1. **系统层面**
   - 禁用透明大页面
   - 调整系统限制（ulimit）
   - 使用 XFS 文件系统

2. **MongoDB 配置**
   - 优化 WiredTiger 缓存大小
   - 调整连接池参数
   - 配置适当的写关注

3. **容器配置**
   - 使用主机网络模式
   - 调整 CPU 份额
   - 配置内存限制

### 监控指标

1. **基础指标**
   - CPU 使用率
   - 内存使用
   - 磁盘 IOPS
   - 网络流量

2. **MongoDB 指标**
   - 操作延迟
   - 连接数
   - 队列长度
   - 复制延迟

3. **分片特定指标**
   - 块分布
   - 平衡器状态
   - 分片大小
   - 跨分片查询

