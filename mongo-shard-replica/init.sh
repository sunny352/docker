#!/bin/bash

# 可配置部分
CLUSTER_NAME="mongo-cluster1"  # 集群名称
BASE_PORT=27017               # 基础端口号
MONGO_VERSION="5.0"          # MongoDB版本
MONGO_USERNAME="root"        # MongoDB用户名
MONGO_PASSWORD="123456"      # MongoDB密码

# 端口配置
CONFIG_PORT=$BASE_PORT
MONGOS_PORT=$((BASE_PORT + 1))
SHARD1_PORT=$((BASE_PORT + 2))
SHARD2_PORT=$((BASE_PORT + 3))

# 添加IP获取函数
get_host_ip() {
    case "$(uname -s)" in
        Darwin)
            # MacOS
            host_ip=$(ipconfig getifaddr en0)
            ;;
        Linux)
            # Linux
            host_ip=$(hostname -I | awk '{print $1}')
            ;;
        *)
            echo "不支持的操作系统"
            exit 1
            ;;
    esac
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
cat > ./${CLUSTER_NAME}/docker-compose.yml <<EOF
version: '3.7'
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
docker-compose up -d

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
wait_for_config_server_ready() {
    local container=$1
    local max_attempts=30
    local attempt=1
    
    echo "等待Config Server完全就绪..."
    while [ $attempt -le $max_attempts ]; do
        # 只检查副本集状态
        local rs_status=$(docker exec ${container} mongosh --quiet --eval "JSON.stringify(rs.status())")
        if [[ $rs_status == *"\"ok\":1"* ]] && [[ $rs_status == *"\"stateStr\":\"PRIMARY\""* ]]; then
            echo "Config Server已完全就绪!"
            return 0
        fi
        echo "尝试 $attempt/$max_attempts ..."
        attempt=$((attempt + 1))
        sleep 3
    done
    
    echo "Config Server未能完全就绪!"
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
if ! wait_for_config_server_ready "${CLUSTER_NAME}_configsvr"; then
    echo "Config Server初始化失败"
    exit 1
fi

# 等待额外的时间确保副本集完全初始化
sleep 5

# 在Config Server上创建管理员用户（修改用户创建命令）
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
    print(JSON.stringify({ok:1,message:'User created successfully'}));
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

echo "等待用户创建生效..."
sleep 2

# 验证用户创建（修改验证命令）
echo "验证Config Server用户..."
VERIFY_CMD="try {
    const admin = db.getSiblingDB('admin');
    const auth = admin.auth('${MONGO_USERNAME}', '${MONGO_PASSWORD}');
    if(!auth) {
        print(JSON.stringify({ok:0,authenticated:false,error:'Auth failed'}));
        quit(1);
    }
    try {
        const testColl = admin.testauth;
        const writeResult = testColl.insertOne({test: 1, timestamp: new Date()});
        if(writeResult.acknowledged) {
            testColl.drop();
            print(JSON.stringify({ok:1,authenticated:true,writeTest:'success'}));
        } else {
            print(JSON.stringify({ok:0,authenticated:true,writeTest:'failed'}));
            quit(1);
        }
    } catch(err) {
        print(JSON.stringify({ok:0,authenticated:true,writeError:err.message}));
        quit(1);
    }
} catch(err) {
    print(JSON.stringify({ok:0,error:err.message}));
    quit(1);
}"

result=$(docker exec ${CLUSTER_NAME}_configsvr mongosh --quiet --eval "$VERIFY_CMD")
echo "验证结果: $result"

if [[ $result != *"\"ok\":1"* ]] || [[ $result != *"\"authenticated\":true"* ]]; then
    echo "Config Server用户验证失败！"
    echo "请检查日志："
    docker exec ${CLUSTER_NAME}_configsvr mongosh --eval "db.adminCommand('getCmdLineOpts')"
    docker logs ${CLUSTER_NAME}_configsvr
    exit 1
fi

# 再次验证是否可以执行管理命令
ADMIN_VERIFY_CMD="try {
    const admin = db.getSiblingDB('admin');
    if(!admin.auth('${MONGO_USERNAME}', '${MONGO_PASSWORD}')) {
        print(JSON.stringify({ok:0,error:'Auth failed'}));
        quit(1);
    }
    const status = admin.runCommand({serverStatus: 1});
    if(status.ok !== 1) {
        print(JSON.stringify({ok:0,error:'Failed to get server status'}));
        quit(1);
    }
    print(JSON.stringify({ok:1,adminCommand:'success'}));
} catch(err) {
    print(JSON.stringify({ok:0,error:err.message}));
    quit(1);
}"

result=$(docker exec ${CLUSTER_NAME}_configsvr mongosh --quiet --eval "$ADMIN_VERIFY_CMD")
if [[ $result != *"\"ok\":1"* ]]; then
    echo "Config Server管理命令验证失败！"
    echo "验证结果: $result"
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
wait_for_primary "${CLUSTER_NAME}_shard1"
wait_for_primary "${CLUSTER_NAME}_shard2"


# 添加用户创建函数
create_admin_user() {
    local container=$1
    local max_attempts=3
    local attempt=1
    
    echo "在 ${container} 上创建管理员用户..."
    while [ $attempt -le $max_attempts ]; do
        local create_cmd="try {
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
            print(JSON.stringify({ok:1,message:'User created successfully'}));
        } catch(err) {
            print(JSON.stringify({ok:0,error:err.message}));
            quit(1);
        }"
        
        local result=$(docker exec ${container} mongosh --quiet --eval "$create_cmd")
        echo "用户创建结果: $result"
        
        if [[ $result == *"\"ok\":1"* ]]; then
            # 验证用户创建
            local verify_cmd="try {
                const admin = db.getSiblingDB('admin');
                const auth = admin.auth('${MONGO_USERNAME}', '${MONGO_PASSWORD}');
                if(auth) {
                    print(JSON.stringify({ok:1,authenticated:true}));
                } else {
                    print(JSON.stringify({ok:0,authenticated:false}));
                    quit(1);
                }
            } catch(err) {
                print(JSON.stringify({ok:0,error:err.message}));
                quit(1);
            }"
            
            local verify_result=$(docker exec ${container} mongosh --quiet --eval "$verify_cmd")
            if [[ $verify_result == *"\"ok\":1"* ]] && [[ $verify_result == *"\"authenticated\":true"* ]]; then
                echo "${container} 用户创建和验证成功"
                return 0
            fi
        fi
        
        echo "尝试 $attempt/$max_attempts ..."
        attempt=$((attempt + 1))
        sleep 2
    done
    
    echo "${container} 创建管理员用户失败"
    return 1
}


# 在分片上创建用户并验证
for shard in "shard1" "shard2"; do
    if ! create_admin_user "${CLUSTER_NAME}_${shard}"; then
        echo "${shard} 用户创建失败"
        exit 1
    fi
done

# 等待 mongos 就绪
wait_for_mongodb "${CLUSTER_NAME}_mongos"

# 直接使用Config Server的管理员账户通过mongos添加分片
ADD_SHARDS_CMD="try {
    const admin = db.getSiblingDB('admin');
    if(!admin.auth('${MONGO_USERNAME}', '${MONGO_PASSWORD}')) {
        print(JSON.stringify({ok:0,error:'Auth failed'}));
        quit(1);
    }
    const result1 = sh.addShard('${CLUSTER_NAME}_shard1rs/${HOST_IP}:${SHARD1_PORT}');
    const result2 = sh.addShard('${CLUSTER_NAME}_shard2rs/${HOST_IP}:${SHARD2_PORT}');
    print(JSON.stringify({ok:1,shard1:result1,shard2:result2}));
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

# 验证集群状态
CHECK_STATUS_CMD="try {
    const admin = db.getSiblingDB('admin');
    if(!admin.auth('${MONGO_USERNAME}', '${MONGO_PASSWORD}')) {
        print(JSON.stringify({ok:0,error:'Auth failed'}));
        quit(1);
    }
    const status = sh.status();
    print(JSON.stringify({ok:1,status:status}));
} catch(err) {
    print(JSON.stringify({ok:0,error:err.message}));
    quit(1);
}"
echo "正在执行验证集群状态命令："
result=$(docker exec ${CLUSTER_NAME}_mongos mongosh --quiet --eval "$CHECK_STATUS_CMD")
echo "集群状态验证结果: $result"

# 修改验证用户创建部分的判断逻辑
VERIFY_ADMIN_CMD="try {
    const admin = db.getSiblingDB('admin');
    if(!admin.auth('${MONGO_USERNAME}', '${MONGO_PASSWORD}')) {
        print(JSON.stringify({ok:0,error:'Auth failed'}));
        quit(1);
    }
    const status = db.runCommand({connectionStatus: 1});
    print(JSON.stringify({ok:1,status:status}));
} catch(err) {
    print(JSON.stringify({ok:0,error:err.message}));
    quit(1);
}"

echo "验证管理员用户..."
result=$(docker exec ${CLUSTER_NAME}_mongos mongosh --quiet --eval "$VERIFY_ADMIN_CMD")
echo "验证结果: $result"

# 修改判断条件：检查是否有认证用户
if [[ $result == *"\"ok\":1"* ]] && [[ $result == *"\"authenticatedUsers\""* ]]; then
    # 检查是否包含admin用户
    if [[ $result == *"\"user\":\"${MONGO_USERNAME}\""* ]] && [[ $result == *"\"db\":\"admin\""* ]]; then
        echo "管理员用户验证成功！"
        echo "验证状态: 已认证用户列表中包含 ${MONGO_USERNAME}@admin"
    else
        echo "管理员用户验证失败！未找到${MONGO_USERNAME}用户"
        exit 1
    fi
else
    echo "管理员用户验证失败！"
    echo "验证结果: $result"
    exit 1
fi

# 部署完成提示
echo "MongoDB分片集群部署完成！"
echo "==================================="
echo "连接说明："
echo "1. 如果已安装mongosh客户端，可以使用以下命令连接："
echo "mongosh \"mongodb://${MONGO_USERNAME}:${MONGO_PASSWORD}@${HOST_IP}:${MONGOS_PORT}/admin?authSource=admin\""
echo ""
echo "2. 如果使用MongoDB Compass图形界面工具连接，使用以下连接串："
echo "mongodb://${MONGO_USERNAME}:${MONGO_PASSWORD}@${HOST_IP}:${MONGOS_PORT}/admin?authSource=admin"
echo ""
echo "3. 如果从其他应用程序连接，使用以下连接串："
echo "mongodb://${MONGO_USERNAME}:${MONGO_PASSWORD}@${HOST_IP}:${MONGOS_PORT}/admin?authSource=admin&directConnection=true"
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
echo "     docker run --rm -it mongo:${MONGO_VERSION} mongosh \"mongodb://${MONGO_USERNAME}:${MONGO_PASSWORD}@${HOST_IP}:${MONGOS_PORT}/admin?authSource=admin\""
echo "==================================="