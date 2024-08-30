#!/bin/bash

#如果不存在mongo-keyfile文件，则创建
if [ ! -f mongo-keyfile ]; then
    echo "找不到mongo-keyfile文件，创建中..."
    openssl rand -base64 756 > mongo-keyfile
    chmod 400 mongo-keyfile
    chown 999:999 mongo-keyfile
fi

#如果不存在init-mongo.js文件，则创建
if [ ! -f init-mongo.js ]; then
    echo "找不到init-mongo.js文件，创建中..."
    echo "rs.initiate();" > init-mongo.js
fi

#启动docker-compose
echo "启动docker-compose"
docker compose up -d