#!/bin/bash

# 默认配置
DEFAULT_CLUSTER_NAME="mongo-cluster1"
DEFAULT_BASE_PORT=27017
DEFAULT_MONGO_VERSION="5.0"
DEFAULT_MONGO_USERNAME="root"
DEFAULT_MONGO_PASSWORD="123456"

# 帮助信息
show_usage() {
    echo "用法: $0 [选项]"
    echo "选项:"
    echo "  -h, --help                显示此帮助信息"
    echo "  -n, --name NAME           设置集群名称 (默认: ${DEFAULT_CLUSTER_NAME})"
    echo "  -p, --port PORT           设置基础端口号 (默认: ${DEFAULT_BASE_PORT})"
    echo "                            将会使用连续的4个端口:"
    echo "                            - PORT:   mongos路由服务"
    echo "                            - PORT+1: config配置服务"
    echo "                            - PORT+2: shard1分片服务"
    echo "                            - PORT+3: shard2分片服务"
    echo "  -v, --version VERSION     设置MongoDB版本 (默认: ${DEFAULT_MONGO_VERSION})"
    echo "  -u, --username USERNAME   设置MongoDB用户名 (默认: ${DEFAULT_MONGO_USERNAME})"
    echo "  -w, --password PASSWORD   设置MongoDB密码 (默认: ${DEFAULT_MONGO_PASSWORD})"
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
            MONGO_VERSION="$2"
            shift 2
            ;;
        -u|--username)
            MONGO_USERNAME="$2"
            shift 2
            ;;
        -w|--password)
            MONGO_PASSWORD="$2"
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

# 设置默认值（如果未通过参数指定）
CLUSTER_NAME=${CLUSTER_NAME:-$DEFAULT_CLUSTER_NAME}
BASE_PORT=${BASE_PORT:-$DEFAULT_BASE_PORT}
MONGO_VERSION=${MONGO_VERSION:-$DEFAULT_MONGO_VERSION}
MONGO_USERNAME=${MONGO_USERNAME:-$DEFAULT_MONGO_USERNAME}
MONGO_PASSWORD=${MONGO_PASSWORD:-$DEFAULT_MONGO_PASSWORD}

# 验证必要参数
if ! [[ "$BASE_PORT" =~ ^[0-9]+$ ]] || [ "$BASE_PORT" -lt 1024 ] || [ "$BASE_PORT" -gt 65535 ]; then
    echo "错误: 端口号必须是1024-65535之间的数字"
    exit 1
fi

# 验证端口范围
if [ $((BASE_PORT + 3)) -gt 65535 ]; then
    echo "错误: 基础端口号过大，无法分配连续的4个端口"
    echo "当前配置将会使用以下端口:"
    echo "- $BASE_PORT:  mongos路由服务"
    echo "- $((BASE_PORT + 1)): config配置服务"
    echo "- $((BASE_PORT + 2)): shard1分片服务"
    echo "- $((BASE_PORT + 3)): shard2分片服务"
    exit 1
fi

if [ -z "$MONGO_USERNAME" ] || [ -z "$MONGO_PASSWORD" ]; then
    echo "错误: 用户名和密码不能为空"
    exit 1
fi

# 端口配置
MONGOS_PORT=$BASE_PORT
CONFIG_PORT=$((BASE_PORT + 1))
SHARD1_PORT=$((BASE_PORT + 2))
SHARD2_PORT=$((BASE_PORT + 3))

# 显示端口使用信息
echo "将使用以下端口:"
echo "- $MONGOS_PORT:  mongos路由服务"
echo "- $CONFIG_PORT: config配置服务"
echo "- $SHARD1_PORT: shard1分片服务"
echo "- $SHARD2_PORT: shard2分片服务"
echo

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
for port in $MONGOS_PORT $CONFIG_PORT $SHARD1_PORT $SHARD2_PORT; do
    check_port $port
done

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

# 创建集群目录
mkdir -p ./${CLUSTER_NAME}

# 创建和设置keyFile
openssl rand -base64 756 > ./${CLUSTER_NAME}/mongodb.key
chmod 400 ./${CLUSTER_NAME}/mongodb.key
chown 999:999 ./${CLUSTER_NAME}/mongodb.key

# 生成docker-compose.yml
cat > ./${CLUSTER_NAME}/compose.yaml <<EOF
networks:
  mongo_cluster_net:
    driver: bridge

services:
  # Config Server
  configsvr:
    image: mongo:${MONGO_VERSION}
    container_name: ${CLUSTER_NAME}_configsvr
    command: mongod --configsvr --replSet ${CLUSTER_NAME}_cfgrs --port 27017 --bind_ip_all 
      --keyFile /data/mongodb.key 
      --auth
      --setParameter authenticationMechanisms=SCRAM-SHA-1
    environment:
      TZ: "Asia/Shanghai"
    ports:
      - "${CONFIG_PORT}:27017"
    volumes:
      - ./configsvr:/data/db
      - ./mongodb.key:/data/mongodb.key:ro
    networks:
      - mongo_cluster_net

  # Router
  mongos:
    image: mongo:${MONGO_VERSION}
    container_name: ${CLUSTER_NAME}_mongos
    depends_on:
      - configsvr
    command: mongos --configdb ${CLUSTER_NAME}_cfgrs/${HOST_IP}:${CONFIG_PORT} 
      --port 27017 
      --bind_ip_all 
      --keyFile /data/mongodb.key
      --setParameter authenticationMechanisms=SCRAM-SHA-1
    environment:
      TZ: "Asia/Shanghai"
    ports:
      - "${MONGOS_PORT}:27017"
    volumes:
      - ./mongodb.key:/data/mongodb.key:ro
    networks:
      - mongo_cluster_net

  # Shard 1
  shard1:
    image: mongo:${MONGO_VERSION}
    container_name: ${CLUSTER_NAME}_shard1
    command: mongod --shardsvr --replSet ${CLUSTER_NAME}_shard1rs 
      --port 27017 
      --bind_ip_all 
      --keyFile /data/mongodb.key 
      --auth
      --setParameter authenticationMechanisms=SCRAM-SHA-1
    environment:
      TZ: "Asia/Shanghai"
    ports:
      - "${SHARD1_PORT}:27017"
    volumes:
      - ./shard1:/data/db
      - ./mongodb.key:/data/mongodb.key:ro
    networks:
      - mongo_cluster_net

  # Shard 2
  shard2:
    image: mongo:${MONGO_VERSION}
    container_name: ${CLUSTER_NAME}_shard2
    command: mongod --shardsvr --replSet ${CLUSTER_NAME}_shard2rs 
      --port 27017 
      --bind_ip_all 
      --keyFile /data/mongodb.key 
      --auth
      --setParameter authenticationMechanisms=SCRAM-SHA-1
    environment:
      TZ: "Asia/Shanghai"
    ports:
      - "${SHARD2_PORT}:27017"
    volumes:
      - ./shard2:/data/db
      - ./mongodb.key:/data/mongodb.key:ro
    networks:
      - mongo_cluster_net
EOF

# 启动容器
cd ${CLUSTER_NAME}
docker compose up -d

# 添加JSON解析函数
parse_mongo_result() {
    local result=$1
    if [[ $result == *"ok"*"1"* ]]; then
        return 0
    else
        return 1
    fi
}

# 修改检测函数
wait_for_mongodb() {
    local container_name=$1
    local max_attempts=30
    local attempt=1
    
    echo "等待 ${container_name} 就绪..."
    while [ $attempt -le $max_attempts ]; do
        local result=$(docker exec ${container_name} mongosh --quiet --eval "JSON.stringify(db.adminCommand('ping'))")
        if parse_mongo_result "$result"; then
            echo "${container_name} 已就绪!"
            return 0
        fi
        echo "尝试 $attempt/$max_attempts ..."
        attempt=$((attempt + 1))
        sleep 2
    done
    
    echo "${container_name} 启动超时!"
    exit 1
}

# 修改副本集初始化检测
wait_for_primary() {
    local container=$1
    local max_attempts=30
    local attempt=1
    
    echo "等待 ${container} 成为主节点..."
    while [ $attempt -le $max_attempts ]; do
        local result=$(docker exec ${container} mongosh --quiet --eval "JSON.stringify(rs.isMaster())")
        if [[ $result == *"\"ismaster\":true"* ]]; then
            echo "${container} 已成为主节点!"
            return 0
        fi
        echo "尝试 $attempt/$max_attempts ..."
        attempt=$((attempt + 1))
        sleep 2
    done
    
    echo "${container} 未能成为主节点!"
    exit 1
}

# 替换原有的sleep等待
echo "等待MongoDB容器就绪..."
wait_for_mongodb "${CLUSTER_NAME}_configsvr"
wait_for_mongodb "${CLUSTER_NAME}_shard1"
wait_for_mongodb "${CLUSTER_NAME}_shard2"

# 修改Config Server就绪检测函数
wait_for_replica_ready() {
    local container=$1
    local max_attempts=30
    local attempt=1
    
    echo "等待节点完全就绪..."
    while [ $attempt -le $max_attempts ]; do
        # 检查副本集状态
        local rs_status=$(docker exec ${container} mongosh --quiet --eval "JSON.stringify(rs.status())")
        if [[ $rs_status == *"\"ok\":1"* ]] && [[ $rs_status == *"\"stateStr\":\"PRIMARY\""* ]]; then
            echo "节点已完全就绪!"
            return 0
        fi
        echo "尝试 $attempt/$max_attempts ..."
        attempt=$((attempt + 1))
        sleep 3
    done
    
    echo "节点未能完全就绪!"
    return 1
}

# 修改Config Server初始化和用户创建部分
echo "初始化Config Server副本集..."
CONFIG_INIT_CMD="rs.initiate({
    _id: '${CLUSTER_NAME}_cfgrs',
    configsvr: true,
    members: [
        { _id: 0, host: '${HOST_IP}:${CONFIG_PORT}' }
    ]
})"
echo "$CONFIG_INIT_CMD"
docker exec ${CLUSTER_NAME}_configsvr mongosh --eval "$CONFIG_INIT_CMD"

# 等待Config Server完全就绪
if ! wait_for_replica_ready "${CLUSTER_NAME}_configsvr"; then
    echo "Config Server初始化失败"
    exit 1
fi

# 等待额外的时间确保副本集完全初始化
sleep 5

# 在Config Server上创建管理员用户
echo "在Config Server上创建管理员用户..."
ADMIN_CREATE_CMD="try {
    const admin = db.getSiblingDB('admin');
    admin.createUser({
        user: '${MONGO_USERNAME}',
        pwd: '${MONGO_PASSWORD}',
        roles: [
            { role: 'root', db: 'admin' },
            { role: 'userAdminAnyDatabase', db: 'admin' },
            { role: 'clusterAdmin', db: 'admin' },
            { role: 'readWriteAnyDatabase', db: 'admin' }
        ]
    });
    // 验证用户创建并测试权限
    if(!admin.auth('${MONGO_USERNAME}', '${MONGO_PASSWORD}')) {
        print(JSON.stringify({ok:0,error:'Auth failed'}));
        quit(1);
    }
    // 测试写入权限
    const testColl = admin.testauth;
    const writeResult = testColl.insertOne({test: 1, timestamp: new Date()});
    if(!writeResult.acknowledged) {
        print(JSON.stringify({ok:0,error:'Write test failed'}));
        quit(1);
    }
    testColl.drop();
    print(JSON.stringify({ok:1,message:'User created and verified successfully'}));
} catch(err) {
    print(JSON.stringify({ok:0,error:err.message}));
    quit(1);
}"

result=$(docker exec ${CLUSTER_NAME}_configsvr mongosh --quiet --eval "$ADMIN_CREATE_CMD")
echo "用户创建结果: $result"

if [[ $result != *"\"ok\":1"* ]]; then
    echo "Config Server用户创建失败！"
    exit 1
fi

echo "Config Server用户创建和验证成功！"

# 初始化Shard1副本集
SHARD1_INIT_CMD="rs.initiate({
    _id: '${CLUSTER_NAME}_shard1rs',
    members: [
        { _id: 0, host: '${HOST_IP}:${SHARD1_PORT}' }
    ]
})"
echo "正在执行Shard1副本集初始化命令："
echo "$SHARD1_INIT_CMD"
docker exec ${CLUSTER_NAME}_shard1 mongosh --eval "$SHARD1_INIT_CMD"

# 初始化Shard2副本集
SHARD2_INIT_CMD="rs.initiate({
    _id: '${CLUSTER_NAME}_shard2rs',
    members: [
        { _id: 0, host: '${HOST_IP}:${SHARD2_PORT}' }
    ]
})"
echo "正在执行Shard2副本集初始化命令："
echo "$SHARD2_INIT_CMD"
docker exec ${CLUSTER_NAME}_shard2 mongosh --eval "$SHARD2_INIT_CMD"

# 等待分片副本集初始化
wait_for_replica_ready "${CLUSTER_NAME}_shard1"
wait_for_replica_ready "${CLUSTER_NAME}_shard2"

# 直接使用Config Server的管理员账户通过mongos添加分片
ADD_SHARDS_CMD="try {
    const admin = db.getSiblingDB('admin');
    if(!admin.auth('${MONGO_USERNAME}', '${MONGO_PASSWORD}')) {
        print(JSON.stringify({ok:0,error:'Auth failed'}));
        quit(1);
    }
    const result1 = sh.addShard('${CLUSTER_NAME}_shard1rs/${HOST_IP}:${SHARD1_PORT}');
    const result2 = sh.addShard('${CLUSTER_NAME}_shard2rs/${HOST_IP}:${SHARD2_PORT}');
    // 直接在这里检查集群状态
    const status = sh.status();
    print(JSON.stringify({ok:1,shard1:result1,shard2:result2,status:status}));
} catch(err) {
    print(JSON.stringify({ok:0,error:err.message}));
    quit(1);
}"

echo "正在执行添加分片到集群命令："
result=$(docker exec ${CLUSTER_NAME}_mongos mongosh --quiet --eval "$ADD_SHARDS_CMD")
echo "添加分片结果: $result"

if [[ $result != *"\"ok\":1"* ]]; then
    echo "添加分片失败"
    echo "错误信息: $result"
    exit 1
fi

# 验证最终的管理员用户状态
FINAL_VERIFY_CMD="try {
    const admin = db.getSiblingDB('admin');
    if(!admin.auth('${MONGO_USERNAME}', '${MONGO_PASSWORD}')) {
        print(JSON.stringify({ok:0,error:'Auth failed'}));
        quit(1);
    }
    print(JSON.stringify({ok:1,authenticated:true}));
} catch(err) {
    print(JSON.stringify({ok:0,error:err.message}));
    quit(1);
}"

echo "验证最终管理员用户状态..."
result=$(docker exec ${CLUSTER_NAME}_mongos mongosh --quiet --eval "$FINAL_VERIFY_CMD")

if [[ $result == *"\"ok\":1"* ]] && [[ $result == *"\"authenticated\":true"* ]]; then
    echo "管理员用户最终验证成功！"
else
    echo "管理员用户最终验证失败！"
    echo "验证结果: $result"
    exit 1
fi

# 部署完成提示
echo "MongoDB分片集群部署完成！"
echo "==================================="
echo "连接说明："
echo "1. 如果已安装mongosh客户端，可以使用以下命令连接："
echo "mongosh \"mongodb://${MONGO_USERNAME}:${MONGO_PASSWORD}@${HOST_IP}:${MONGOS_PORT}/admin?authSource=admin&authMechanism=SCRAM-SHA-1\""
echo ""
echo "2. 如果使用MongoDB Compass图形界面工具连接，使用以下连接串："
echo "mongodb://${MONGO_USERNAME}:${MONGO_PASSWORD}@${HOST_IP}:${MONGOS_PORT}/admin?authSource=admin&authMechanism=SCRAM-SHA-1&readPreference=primary&retryWrites=true&w=majority"
echo ""
echo "3. 如果从其他应用程序连接，使用以下连接串："
echo "mongodb://${MONGO_USERNAME}:${MONGO_PASSWORD}@${HOST_IP}:${MONGOS_PORT}/admin?authSource=admin&authMechanism=SCRAM-SHA-1&readPreference=primary&retryWrites=true&w=majority&maxPoolSize=50&minPoolSize=10&maxIdleTimeMS=30000&connectTimeoutMS=10000"
echo ""
echo "注意事项："
echo "1. 如果从其他机器连接，请将 ${HOST_IP} 替换为服务器的实际可访问IP地址"
echo "2. 确保防火墙已开放 ${MONGOS_PORT} 端口"
echo "3. 可以使用以下命令检查端口是否开放："
echo "   nc -zv ${HOST_IP} ${MONGOS_PORT}"
echo ""
echo "4. 如果需要安装mongosh客户端："
echo "   - MacOS: brew install mongosh"
echo "   - Linux: 参考 https://www.mongodb.com/docs/mongodb-shell/install/"
echo "   - 或使用Docker临时测试连接："
echo "     docker run --rm -it mongo:${MONGO_VERSION} mongosh \"mongodb://${MONGO_USERNAME}:${MONGO_PASSWORD}@${HOST_IP}:${MONGOS_PORT}/admin?authSource=admin&authMechanism=SCRAM-SHA-1\""
echo "==================================="

# 生成集群信息和使用说明
cat > README.md <<EOF
# MongoDB分片集群使用说明

## 集群信息
- 集群名称: ${CLUSTER_NAME}
- MongoDB版本: ${MONGO_VERSION}
- 用户名: ${MONGO_USERNAME}
- 密码: ${MONGO_PASSWORD}

## 节点信息
- Mongos路由服务: ${HOST_IP}:${MONGOS_PORT}
- Config配置服务: ${HOST_IP}:${CONFIG_PORT}
- Shard1分片服务: ${HOST_IP}:${SHARD1_PORT}
- Shard2分片服务: ${HOST_IP}:${SHARD2_PORT}

## 连接方式

### 1. 使用mongosh命令行工具
\`\`\`bash
mongosh "mongodb://${MONGO_USERNAME}:${MONGO_PASSWORD}@${HOST_IP}:${MONGOS_PORT}/admin?authSource=admin&authMechanism=SCRAM-SHA-1"
\`\`\`

### 2. 使用MongoDB Compass图形界面工具
连接串：
\`\`\`
mongodb://${MONGO_USERNAME}:${MONGO_PASSWORD}@${HOST_IP}:${MONGOS_PORT}/admin?authSource=admin&authMechanism=SCRAM-SHA-1&readPreference=primary&retryWrites=true&w=majority
\`\`\`

### 3. 应用程序连接
标准连接串（推荐）：
\`\`\`
mongodb://${MONGO_USERNAME}:${MONGO_PASSWORD}@${HOST_IP}:${MONGOS_PORT}/admin?authSource=admin&authMechanism=SCRAM-SHA-1&readPreference=primary&retryWrites=true&w=majority
\`\`\`

高可用连接串（生产环境推荐）：
\`\`\`
mongodb://${MONGO_USERNAME}:${MONGO_PASSWORD}@${HOST_IP}:${MONGOS_PORT}/admin?authSource=admin&authMechanism=SCRAM-SHA-1&readPreference=primary&retryWrites=true&w=majority&maxPoolSize=50&minPoolSize=10&maxIdleTimeMS=30000&connectTimeoutMS=10000&serverSelectionTimeoutMS=5000&socketTimeoutMS=45000&waitQueueTimeoutMS=5000&heartbeatFrequencyMS=10000
\`\`\`

### 连接参数说明
- \`authSource=admin\`: 指定认证数据库
- \`authMechanism=SCRAM-SHA-1\`: 指定认证机制
- \`readPreference=primary\`: 优先从主节点读取数据
- \`retryWrites=true\`: 启用写操作重试
- \`w=majority\`: 写操作需要大多数节点确认
- \`maxPoolSize=50\`: 连接池最大连接数
- \`minPoolSize=10\`: 连接池最小连接数
- \`maxIdleTimeMS=30000\`: 连接最大空闲时间
- \`connectTimeoutMS=10000\`: 连接超时时间
- \`serverSelectionTimeoutMS=5000\`: 服务器选择超时时间
- \`socketTimeoutMS=45000\`: Socket超时时间
- \`waitQueueTimeoutMS=5000\`: 等待队列超时时间
- \`heartbeatFrequencyMS=10000\`: 心跳检测频率

## 代码示例

### Python (pymongo)
\`\`\`python
from pymongo import MongoClient

uri = "mongodb://${MONGO_USERNAME}:${MONGO_PASSWORD}@${HOST_IP}:${MONGOS_PORT}/admin?authSource=admin&authMechanism=SCRAM-SHA-1&readPreference=primary&retryWrites=true&w=majority"
client = MongoClient(uri, 
    maxPoolSize=50,
    minPoolSize=10,
    maxIdleTimeMS=30000,
    connectTimeoutMS=10000,
    serverSelectionTimeoutMS=5000,
    socketTimeoutMS=45000,
    waitQueueTimeoutMS=5000,
    heartbeatFrequencyMS=10000
)
db = client.your_database
\`\`\`

### Node.js (mongodb)
\`\`\`javascript
const { MongoClient } = require('mongodb');

const uri = "mongodb://${MONGO_USERNAME}:${MONGO_PASSWORD}@${HOST_IP}:${MONGOS_PORT}/admin?authSource=admin&authMechanism=SCRAM-SHA-1&readPreference=primary&retryWrites=true&w=majority";
const client = new MongoClient(uri, {
    maxPoolSize: 50,
    minPoolSize: 10,
    maxIdleTimeMS: 30000,
    connectTimeoutMS: 10000,
    serverSelectionTimeoutMS: 5000,
    socketTimeoutMS: 45000,
    waitQueueTimeoutMS: 5000,
    heartbeatFrequencyMS: 10000
});
await client.connect();
const db = client.db('your_database');
\`\`\`

### Java (mongodb-driver-sync)
\`\`\`java
import com.mongodb.MongoClientSettings;
import com.mongodb.ConnectionString;
import com.mongodb.client.MongoClients;
import com.mongodb.client.MongoClient;
import com.mongodb.client.MongoDatabase;

String uri = "mongodb://${MONGO_USERNAME}:${MONGO_PASSWORD}@${HOST_IP}:${MONGOS_PORT}/admin?authSource=admin&authMechanism=SCRAM-SHA-1&readPreference=primary&retryWrites=true&w=majority";
MongoClientSettings settings = MongoClientSettings.builder()
    .applyConnectionString(new ConnectionString(uri))
    .applyToConnectionPoolSettings(builder -> 
        builder.maxSize(50)
               .minSize(10)
               .maxConnectionIdleTime(30000, TimeUnit.MILLISECONDS)
    )
    .applyToSocketSettings(builder ->
        builder.connectTimeout(10000, TimeUnit.MILLISECONDS)
               .readTimeout(45000, TimeUnit.MILLISECONDS)
    )
    .applyToServerSettings(builder ->
        builder.heartbeatFrequency(10000, TimeUnit.MILLISECONDS)
    )
    .build();
MongoClient mongoClient = MongoClients.create(settings);
MongoDatabase database = mongoClient.getDatabase("your_database");
\`\`\`

### Go (mongo-driver)
\`\`\`go
import (
    "context"
    "time"
    "go.mongodb.org/mongo-driver/mongo"
    "go.mongodb.org/mongo-driver/mongo/options"
)

uri := "mongodb://${MONGO_USERNAME}:${MONGO_PASSWORD}@${HOST_IP}:${MONGOS_PORT}/admin?authSource=admin&authMechanism=SCRAM-SHA-1&readPreference=primary&retryWrites=true&w=majority"
opts := options.Client().
    ApplyURI(uri).
    SetMaxPoolSize(50).
    SetMinPoolSize(10).
    SetMaxConnIdleTime(30 * time.Second).
    SetConnectTimeout(10 * time.Second).
    SetServerSelectionTimeout(5 * time.Second).
    SetSocketTimeout(45 * time.Second)

client, err := mongo.Connect(context.TODO(), opts)
db := client.Database("your_database")
\`\`\`

## 常用管理命令

### 1. 查看集群状态
\`\`\`bash
mongosh "mongodb://${MONGO_USERNAME}:${MONGO_PASSWORD}@${HOST_IP}:${MONGOS_PORT}/admin?authSource=admin" --eval "sh.status()"
\`\`\`

### 2. 查看数据库列表
\`\`\`bash
mongosh "mongodb://${MONGO_USERNAME}:${MONGO_PASSWORD}@${HOST_IP}:${MONGOS_PORT}/admin?authSource=admin" --eval "show dbs"
\`\`\`

### 3. 为集合启用分片
\`\`\`bash
# 首先对数据库启用分片
mongosh "mongodb://${MONGO_USERNAME}:${MONGO_PASSWORD}@${HOST_IP}:${MONGOS_PORT}/admin?authSource=admin" --eval 'sh.enableSharding("your_database")'

# 然后对集合启用分片（示例使用_id作为片键）
mongosh "mongodb://${MONGO_USERNAME}:${MONGO_PASSWORD}@${HOST_IP}:${MONGOS_PORT}/admin?authSource=admin" --eval 'sh.shardCollection("your_database.your_collection", {_id: "hashed"})'
\`\`\`

### 4. 查看集群配置
\`\`\`bash
mongosh "mongodb://${MONGO_USERNAME}:${MONGO_PASSWORD}@${HOST_IP}:${MONGOS_PORT}/admin?authSource=admin" --eval "db.getSiblingDB('config').settings.find()"
\`\`\`

## 注意事项
1. 如果从其他机器连接，请将 ${HOST_IP} 替换为服务器的实际可访问IP地址
2. 确保防火墙已开放所需端口（${MONGOS_PORT}-$((MONGOS_PORT+3))）
3. 建议在生产环境中修改默认密码
4. 分片集群的所有操作都应该通过mongos路由进行
5. 建议使用支持MongoDB分片集群的驱动程序版本

## 管理命令

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

### 重启集群
\`\`\`bash
cd ${CLUSTER_NAME}
docker compose restart
\`\`\`

## 故障排查
1. 如果连接失败，请检查：
   - 用户名密码是否正确
   - IP地址和端口是否可访问
   - 防火墙是否开放端口
   - 集群服务是否正常运行

2. 如果分片不均衡，可以：
   - 检查片键选择是否合适
   - 运行手动平衡命令
   - 调整平衡器配置

3. 如果性能问题，建议：
   - 检查索引使用情况
   - 优化查询语句
   - 监控各分片负载
   - 考虑添加更多分片

## 备份和恢复
1. 备份整个集群：
\`\`\`bash
mongodump --uri="mongodb://${MONGO_USERNAME}:${MONGO_PASSWORD}@${HOST_IP}:${MONGOS_PORT}/admin?authSource=admin" --out=/backup/$(date +%Y%m%d)
\`\`\`

2. 恢复备份：
\`\`\`bash
mongorestore --uri="mongodb://${MONGO_USERNAME}:${MONGO_PASSWORD}@${HOST_IP}:${MONGOS_PORT}/admin?authSource=admin" /backup/20240101
\`\`\`

## 监控建议
1. 定期检查集群状态
2. 监控各节点资源使用
3. 设置适当的告警阈值
4. 保持日志定期归档
5. 建立备份恢复机制

祝您使用愉快！
EOF

echo "集群信息和使用说明已保存到 README.md"