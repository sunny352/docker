# mongo单节点副本集

## 功能

* 通过docker compose启动一个mongo单节点副本集

## 原因

* 本地开发环境中，需要一个mongo单节点副本集，有些功能只有在集群模式下可用，比如oplog（watch依赖于集群oplog）

## 使用方式

### 配置选项

init.sh 支持以下参数：

* `-p, --port PORT`: 设置端口号（默认：27017）
* `-r, --replset NAME`: 设置副本集名称（默认：single-rs0）
* `-u, --username USERNAME`: 设置MongoDB用户名（默认：root）
* `-w, --password PASSWORD`: 设置MongoDB密码（默认：123456）
* `--host-ip IP`: 手动指定主机IP（可选）
* `-h, --help`: 显示帮助信息

### 启动

* 运行 init.sh，可以使用上述参数自定义配置，例如：
  ```bash
  ./init.sh --port 27018 --replset my-rs0
  ```

## 说明

* init.sh 脚本会：
  - 自动创建副本集所需的目录结构
  - 创建mongo的集群key文件（如果不存在）
  - 生成 docker-compose.yml 配置文件（如果不存在）
  - 创建并启动docker compose集群
  - 自动初始化副本集

## 技术细节

* 使用 MongoDB 5.0 及以上版本
* 默认时区设置为 Asia/Shanghai
* 自动配置副本集认证
* 数据持久化存储在 ./mongo 目录