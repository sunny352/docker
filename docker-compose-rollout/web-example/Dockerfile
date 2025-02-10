# 这是一个用于测试滚动更新脚本的示例服务
# 实际使用时可以替换为你自己的应用镜像
# 关键点是需要配置 HEALTHCHECK 指令

FROM golang:1.23-alpine AS builder

# 设置构建参数
ARG VERSION=v1.0.0

WORKDIR /app
COPY src/ .
# 使用 ldflags 在构建时注入版本号，禁用 CGO 以获得静态二进制文件
ENV CGO_ENABLED=0
RUN go build -ldflags "-X main.VERSION=${VERSION}" -o main main.go

FROM alpine/curl:latest
WORKDIR /app
COPY --from=builder /app/main .

EXPOSE 8080

# 健康检查配置示例
# 实际使用时根据你的应用调整检查命令和参数
HEALTHCHECK --interval=5s --timeout=3s --retries=3 \
    CMD curl -f http://localhost:8080/ || exit 1

# 使用exec格式的CMD，确保信号能正确传递给应用
CMD ["./main"]

# 确保容器接收到SIGTERM信号时能优雅退出
STOPSIGNAL SIGTERM