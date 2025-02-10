package main

import (
    "context"
    "fmt"
    "log"
    "net/http"
    "os"
    "os/signal"
    "syscall"
    "time"
)

// VERSION 可以在构建时通过 -ldflags 修改
var VERSION = "v1.0.0"

func main() {
    // 创建 HTTP server
    server := &http.Server{
        Addr: ":8080",
        Handler: http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
            fmt.Fprintf(w, VERSION)
        }),
    }

    // 创建一个通道来接收操作系统的信号
    done := make(chan os.Signal, 1)
    signal.Notify(done, os.Interrupt, syscall.SIGINT, syscall.SIGTERM)

    go func() {
        if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
            log.Fatalf("监听失败: %v\n", err)
        }
    }()

    log.Printf("服务启动成功，监听端口 :8080")

    // 等待中断信号
    <-done
    log.Print("服务关闭中...")

    // 创建一个5秒超时的上下文
    ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
    defer cancel()

    // 优雅关闭服务
    if err := server.Shutdown(ctx); err != nil {
        log.Fatalf("服务关闭出错: %v\n", err)
    }

    log.Print("服务已关闭")
}