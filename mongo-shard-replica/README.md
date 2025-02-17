# MongoDB分片副本集集群

## 简介
该项目使用Docker和Docker Compose部署一个MongoDB分片副本集集群，包括一个Config Server、两个Shard和一个Mongos路由器。

## 使用说明

### 1. 克隆项目
```bash
git clone <repository-url>
cd mongo-shard-replica
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

### 3. 连接MongoDB集群
初始化完成后，脚本会显示详细的连接信息。以下是连接方式示例：

- 使用mongosh客户端连接：
```bash
mongosh "mongodb://<username>:<password>@<host-ip>:<port>/admin?authSource=admin"
```
- 使用MongoDB Compass连接：
```bash
mongodb://<username>:<password>@<host-ip>:<port>/admin?authSource=admin
```
- 从其他应用程序连接：
```bash
mongodb://<username>:<password>@<host-ip>:<port>/admin?authSource=admin&directConnection=true
```

### 注意事项
1. 如果从其他机器连接，请将 `<host-ip>` 替换为服务器的实际可访问IP地址
2. 确保防火墙已开放所需端口（默认为 27017-27020）
3. 可以使用以下命令检查端口是否开放：
```bash
nc -zv <host-ip> <port>
```
4. 如果需要安装mongosh客户端：
   - MacOS: `brew install mongosh`
   - Linux: 参考 [MongoDB Shell 安装文档](https://www.mongodb.com/docs/mongodb-shell/install/)
   - 或使用Docker临时测试连接：
```bash
docker run --rm -it mongo:<version> mongosh "mongodb://<username>:<password>@<host-ip>:<port>/admin?authSource=admin"
```

### 目录结构
初始化完成后，会在指定的集群名称目录下创建以下文件和目录：
```
<cluster-name>/
├── compose.yaml          # Docker Compose 配置文件
├── mongodb.key          # MongoDB 认证密钥文件
├── configsvr/          # Config Server 数据目录
├── shard1/            # Shard1 数据目录
└── shard2/            # Shard2 数据目录
```

### 常见问题
1. 端口被占用
   - 脚本会自动检查端口占用情况
   - 如果端口被占用，可以使用 `-p` 参数指定其他起始端口

2. 无法获取主机IP
   - 脚本会自动尝试多种方法获取主机IP
   - 如果自动获取失败，可以使用 `--host-ip` 参数手动指定IP地址

3. 权限问题
   - 由于需要设置 mongodb.key 文件权限，脚本需要使用 sudo 运行
   - 确保运行脚本的用户有足够的权限

