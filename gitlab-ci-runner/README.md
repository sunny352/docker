# Docker GitLab CI Runner 安装指南

这个项目提供了一个使用 Docker 快速部署 GitLab CI Runner 的解决方案。

## 前置要求

- Docker
- Docker Compose
- 可以访问 GitLab 服务器
- GitLab Runner 注册令牌

## 快速开始

1. 克隆此仓库:
```bash
git clone <repository-url>
cd gitlab-ci-runner
```

2. 修改配置信息:
编辑 `init.sh` 文件,更新以下变量:
- `GITLAB_URL`: 你的 GitLab 服务器地址
- `REGISTRATION_TOKEN`: 你的 Runner 注册令牌
- `RUNNER_DESCRIPTION`: Runner 描述
- `RUNNER_TAGS`: Runner 标签

3. 运行安装脚本:
```bash
chmod +x init.sh
./init.sh
```

## 配置说明

本项目使用 Docker Compose 来管理容器,主要配置包括:

- 使用最新版本的 gitlab/gitlab-runner 镜像
- 自动重启功能
- 挂载 Docker socket 以支持 Docker executor
- 持久化 Runner 配置

## 常用命令

```bash
# 启动服务
docker compose up -d

# 查看日志
docker compose logs gitlab-runner

# 停止服务
docker compose down

# 查看 Runner 状态
docker compose exec gitlab-runner gitlab-runner list
```

## 故障排查

1. 如果 Runner 无法注册,检查:
   - GitLab URL 是否正确
   - 注册令牌是否有效
   - 网络连接是否正常

2. 如果容器无法启动,检查:
   - Docker 服务是否运行
   - 端口是否被占用
   - 系统权限是否足够

## 参考资料

- [GitLab Runner 官方文档](https://docs.gitlab.com/runner/)
- [Docker Hub - gitlab/gitlab-runner](https://hub.docker.com/r/gitlab/gitlab-runner)
