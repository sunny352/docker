#!/bin/bash

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
sleep 10

#初始化mongo
echo "初始化mongo"
docker exec -it mongo-rs0 mongo --authenticationDatabase admin -u root -p 123456 --eval "rs.initiate({_id: 'rs0', members: [{_id: 0, host: '10.0.68.124:27017'}]})"