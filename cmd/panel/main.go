package main

import (
    "flag"
    "log"

    "init-panel/internal/httpserver"
)

func main() {
    webDir := flag.String("web-dir", "./web", "web static directory")
    port := flag.Int("port", 80, "http listen port")
    flag.Parse()

    cfg := httpserver.Config{
        WebDir: *webDir,
        Port:   *port,
    }

    srv, err := httpserver.NewServer(cfg)
    if err != nil {
        log.Fatalf("init server failed: %v", err)
    }

    log.Printf("Init Panel starting on :%d, webDir=%s", cfg.Port, cfg.WebDir)
    if err := srv.Start(); err != nil {
        log.Fatalf("server stopped: %v", err)
    }
}
