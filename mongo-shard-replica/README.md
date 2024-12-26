# MongoDB分片副本集集群

## 简介
该项目使用Docker和Docker Compose部署一个MongoDB分片副本集集群，包括一个Config Server、两个Shard和一个Mongos路由器。

## 使用说明

### 1. 克隆项目
```bash
git clone <repository-url>
cd mongo-shard-replica
```

### 2. 配置参数
在`init.sh`脚本中，可以根据需要修改以下参数：
- `CLUSTER_NAME`: 集群名称
- `BASE_PORT`: 基础端口号
- `MONGO_VERSION`: MongoDB版本
- `MONGO_USERNAME`: MongoDB用户名
- `MONGO_PASSWORD`: MongoDB密码

### 3. 运行初始化脚本
```bash
chmod +x init.sh
./init.sh
```

### 4. 连接MongoDB集群
- 使用mongosh客户端连接：
```bash
mongosh "mongodb://<MONGO_USERNAME>:<MONGO_PASSWORD>@<HOST_IP>:<MONGOS_PORT>/admin?authSource=admin"
```
- 使用MongoDB Compass连接：
```bash
mongodb://<MONGO_USERNAME>:<MONGO_PASSWORD>@<HOST_IP>:<MONGOS_PORT>/admin?authSource=admin
```
- 从其他应用程序连接：
```bash
mongodb://<MONGO_USERNAME>:<MONGO_PASSWORD>@<HOST_IP>:<MONGOS_PORT>/admin?authSource=admin&directConnection=true
```

### 注意事项
1. 如果从其他机器连接，请将 `<HOST_IP>` 替换为服务器的实际可访问IP地址。
2. 确保防火墙已开放 `<MONGOS_PORT>` 端口。
3. 可以使用以下命令检查端口是否开放：
```bash
nc -zv <HOST_IP> <MONGOS_PORT>
```
4. 如果需要安装mongosh客户端：
   - MacOS: `brew install mongosh`
   - Linux: 参考 [MongoDB Shell 安装文档](https://www.mongodb.com/docs/mongodb-shell/install/)
   - 或使用Docker临时测试连接：
```bash
docker run --rm -it mongo:<MONGO_VERSION> mongosh "mongodb://<MONGO_USERNAME>:<MONGO_PASSWORD>@<HOST_IP>:<MONGOS_PORT>/admin?authSource=admin"
```

