package httpserver

import (
    "fmt"
    "log"
    "net/http"
    "os"
    "path/filepath"

    "init-panel/internal/routes"
)

type Config struct {
    WebDir string
    Port   int
}

type Server struct {
    cfg Config
    mux *http.ServeMux
}

func NewServer(cfg Config) (*Server, error) {
    abs, err := filepath.Abs(cfg.WebDir)
    if err != nil {
        return nil, err
    }
    cfg.WebDir = abs

    if _, err := os.Stat(cfg.WebDir); err != nil {
        return nil, fmt.Errorf("web dir not found: %s", cfg.WebDir)
    }

    mux := http.NewServeMux()
    s := &Server{cfg: cfg, mux: mux}

    // 注册 API 路由
    routes.RegisterAll(mux)

    // 静态文件
    fs := http.FileServer(http.Dir(cfg.WebDir))
    mux.Handle("/", fs)

    return s, nil
}

func (s *Server) Start() error {
    addr := fmt.Sprintf("0.0.0.0:%d", s.cfg.Port)
    log.Printf("listening on %s", addr)
    return http.ListenAndServe(addr, s.mux)
}
