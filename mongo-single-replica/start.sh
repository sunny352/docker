#!/bin/bash

port=27017
replSetName=rs0
ip=$(hostname -I | awk '{print $1}')

echo "当前主机IP: $ip"
echo "当前端口: $port"
echo "当前副本集名称: $replSetName"

#如果不存在mongo-keyfile文件，则创建
if [ ! -f mongo-keyfile ]; then
    echo "找不到mongo-keyfile文件，创建中..."
    openssl rand -base64 756 > mongo-keyfile
    chmod 400 mongo-keyfile
    chown 999:999 mongo-keyfile
fi

#如果不存在docker-compose.yml文件，则创建
if [ ! -f docker-compose.yml ]; then
    echo "找不到docker-compose.yml文件，创建中..."
    cat > docker-compose.yml << EOL
version: '3'
services:
    mongo:
        image: mongo:5.0 #需要MongoDB 5.0以上版本
        container_name: mongo-${replSetName}
        ports:
            - "${port}:27017"
        expose:
            - "27017"
        restart: always
        environment:
            MONGO_INITDB_ROOT_USERNAME: "root"
            MONGO_INITDB_ROOT_PASSWORD: "123456"
            TZ: "Asia/Shanghai"
        volumes:
            - "./mongo:/data/db"
            - "./mongo-keyfile:/etc/mongo-keyfile:ro"
        command: [ "mongod", "--replSet", "${replSetName}", "--keyFile", "/etc/mongo-keyfile" ]
EOL
fi

#启动docker-compose
echo "启动docker-compose"
docker compose up -d

#等待mongo启动
echo "等待mongo启动"
for i in {1..300}; do
    docker exec -it mongo-${replSetName} mongo --eval "db.adminCommand('ping')" > /dev/null 2>&1 && break
    sleep 1
done

#初始化mongo
echo "初始化mongo"
script="rs.initiate({_id: '${replSetName}', members: [{_id: 0, host: '$ip:$port'}]})"
echo "执行脚本: $script"
docker exec -it mongo-${replSetName} mongosh --authenticationDatabase admin -u root -p 123456 --host $ip --eval "$script"