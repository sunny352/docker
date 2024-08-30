#!/bin/bash

ip=$(hostname -I | awk '{print $1}')
echo "当前主机IP: $ip"

#如果不存在mongo-keyfile文件，则创建
if [ ! -f mongo-keyfile ]; then
    echo "找不到mongo-keyfile文件，创建中..."
    openssl rand -base64 756 > mongo-keyfile
    chmod 400 mongo-keyfile
    chown 999:999 mongo-keyfile
fi

#启动docker-compose
echo "启动docker-compose"
docker compose up -d

#等待mongo启动
echo "等待mongo启动"
for i in {1..300}; do
    docker exec -it mongo-rs0 mongo --eval "db.adminCommand('ping')" > /dev/null 2>&1 && break
    sleep 1
done

#初始化mongo
echo "初始化mongo"
script="rs.initiate({_id: 'rs0', members: [{_id: 0, host: '$ip:27017'}]})"
echo "执行脚本: $script"
docker exec -it mongo-rs0 mongosh --authenticationDatabase admin -u root -p 123456 --eval "$script"