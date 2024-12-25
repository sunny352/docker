# mongo单节点副本集

## 功能

* 通过docker compose启动一个mongo单节点副本集

## 原因

* 本地开发环境中，需要一个mongo单节点副本集，有些功能只有在集群模式下可用，比如oplog（watch依赖于集群oplog）

## 使用方式

* 启动：运行start.sh，默认端口27017，集群名为rs0，可在start.sh中修改
* 停止：运行stop.sh

## 说明

* start.sh脚本会创建mongo的集群key文件、创建并启动docker compose集群并且初始化集群
* stop.sh脚本会停止docker compose集群