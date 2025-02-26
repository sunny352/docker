#!/bin/bash

# 默认配置
DEFAULT_PORT=27017
DEFAULT_REPLSET_NAME="single-rs0"
DEFAULT_MONGO_USERNAME="root"
DEFAULT_MONGO_PASSWORD="123456"

# 帮助信息
show_usage() {
    echo "用法: $0 [选项]"
    echo "选项:"
    echo "  -h, --help                显示此帮助信息"
    echo "  -p, --port PORT           设置端口号 (默认: ${DEFAULT_PORT})"
    echo "  -r, --replset NAME        设置副本集名称 (默认: ${DEFAULT_REPLSET_NAME})"
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
        -p|--port)
            PORT="$2"
            shift 2
            ;;
        -r|--replset)
            REPLSET_NAME="$2"
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
PORT=${PORT:-$DEFAULT_PORT}
REPLSET_NAME=${REPLSET_NAME:-$DEFAULT_REPLSET_NAME}
MONGO_USERNAME=${MONGO_USERNAME:-$DEFAULT_MONGO_USERNAME}
MONGO_PASSWORD=${MONGO_PASSWORD:-$DEFAULT_MONGO_PASSWORD}

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
echo "当前端口: $PORT"
echo "当前副本集名称: $REPLSET_NAME"

# 创建集群目录
mkdir -p ./${REPLSET_NAME}

#如果不存在mongo-keyfile文件，则创建
if [ ! -f ./${REPLSET_NAME}/mongo-keyfile ]; then
    echo "找不到mongo-keyfile文件，创建中..."
    openssl rand -base64 756 > ./${REPLSET_NAME}/mongo-keyfile
    chmod 400 ./${REPLSET_NAME}/mongo-keyfile
    chown 999:999 ./${REPLSET_NAME}/mongo-keyfile
fi

#如果不存在docker-compose.yml文件，则创建
if [ ! -f ./${REPLSET_NAME}/docker-compose.yml ]; then
    echo "找不到docker-compose.yml文件，创建中..."
    cat > ./${REPLSET_NAME}/docker-compose.yml << EOL
version: '3'
services:
    mongo:
        image: mongo:5.0 #需要MongoDB 5.0以上版本
        container_name: mongo-${REPLSET_NAME}
        ports:
            - "${PORT}:27017"
        expose:
            - "27017"
        restart: always
        environment:
            MONGO_INITDB_ROOT_USERNAME: "${MONGO_USERNAME}"
            MONGO_INITDB_ROOT_PASSWORD: "${MONGO_PASSWORD}"
            TZ: "Asia/Shanghai"
        volumes:
            - "./mongo:/data/db"
            - "./mongo-keyfile:/etc/mongo-keyfile:ro"
        command: [ "mongod", "--replSet", "${REPLSET_NAME}", "--keyFile", "/etc/mongo-keyfile" ]
EOL
fi

#启动docker compose
echo "启动docker compose"
cd ./${REPLSET_NAME}
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

# 等待mongo启动
echo "等待mongo启动"
max_attempts=30
attempt=1
while [ $attempt -le $max_attempts ]; do
    result=$(docker exec -it mongo-${REPLSET_NAME} mongosh --quiet --eval "JSON.stringify(db.adminCommand('ping'))" 2>/dev/null)
    if parse_mongo_result "$result"; then
        echo "MongoDB已就绪!"
        break
    fi
    echo "尝试 $attempt/$max_attempts ..."
    attempt=$((attempt + 1))
    sleep 2
    
    if [ $attempt -gt $max_attempts ]; then
        echo "MongoDB启动超时!"
        exit 1
    fi
done

#初始化mongo
echo "初始化mongo"
INIT_CMD="rs.initiate({_id: '${REPLSET_NAME}', members: [{_id: 0, host: '${HOST_IP}:${PORT}'}]})"
echo "执行脚本: $INIT_CMD"
docker exec -it mongo-${REPLSET_NAME} mongosh --authenticationDatabase admin -u ${MONGO_USERNAME} -p ${MONGO_PASSWORD} --host ${HOST_IP} --eval "$INIT_CMD"