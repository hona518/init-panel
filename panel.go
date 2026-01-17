package main

import (
    "encoding/json"
    "flag"
    "fmt"
    "log"
    "net/http"
    "os"
    "time"
)

var (
    certFile string
    keyFile  string
    webDir   string
    addr     string
)

func init() {
    flag.StringVar(&certFile, "cert", "/opt/reality-panel/certs/panel.crt", "SSL certificate file")
    flag.StringVar(&keyFile, "key", "/opt/reality-panel/certs/panel.key", "SSL key file")
    flag.StringVar(&webDir, "web", "/opt/reality-panel/web", "Web static files directory")
    flag.StringVar(&addr, "addr", ":8443", "Listen address")
}

func main() {
    flag.Parse()

    if _, err := os.Stat(certFile); err != nil {
        log.Fatalf("证书文件不存在: %s, err: %v", certFile, err)
    }
    if _, err := os.Stat(keyFile); err != nil {
        log.Fatalf("私钥文件不存在: %s, err: %v", keyFile, err)
    }

    mux := http.NewServeMux()
    registerAPIRoutes(mux)

    // 静态文件（前端）
    fs := http.FileServer(http.Dir(webDir))
    mux.Handle("/", fs)

    server := &http.Server{
        Addr:         addr,
        Handler:      logMiddleware(mux),
        ReadTimeout:  10 * time.Second,
        WriteTimeout: 30 * time.Second,
        IdleTimeout:  60 * time.Second,
    }

    log.Printf("Reality Panel 启动中: https://%s\n", addr)
    log.Printf("使用证书: %s", certFile)
    log.Printf("前端目录: %s", webDir)

    if err := server.ListenAndServeTLS(certFile, keyFile); err != nil {
        log.Fatalf("HTTPS 服务启动失败: %v", err)
    }
}

func registerAPIRoutes(mux *http.ServeMux) {
    // Ping
    mux.HandleFunc("/api/ping", PingHandler)

    // Reality 模块
    mux.HandleFunc("/api/reality/info", GetRealityInfo)
    mux.HandleFunc("/api/reality/update", UpdateRealityConfig)
    mux.HandleFunc("/api/reality/reset-keys", ResetRealityKeys)
    mux.HandleFunc("/api/reality/restart", RestartRealityService)

    // 流量模块
    mux.HandleFunc("/api/traffic/info", GetTrafficInfo)
    mux.HandleFunc("/api/traffic/reset", ResetTraffic)

    // 系统模块
    mux.HandleFunc("/api/system/info", GetSystemInfo)
    mux.HandleFunc("/api/system/timezone", SetTimezone)
    mux.HandleFunc("/api/system/swap", SetSwap)

    // 防火墙模块
    mux.HandleFunc("/api/firewall/list", GetFirewallRules)
    mux.HandleFunc("/api/firewall/open", OpenFirewallPort)
    mux.HandleFunc("/api/firewall/close", CloseFirewallPort)

    // 服务模块
    mux.HandleFunc("/api/service/status", GetServiceStatus)
    mux.HandleFunc("/api/service/restart", RestartService)

    // 配置模块
    mux.HandleFunc("/api/config/view", ViewConfig)
    mux.HandleFunc("/api/config/save", SaveConfig)

    // BBR 模块
    mux.HandleFunc("/api/bbr/status", GetBBRStatus)
    mux.HandleFunc("/api/bbr/enable", EnableBBR)

    // 网络优先级模块
    mux.HandleFunc("/api/network/priority", GetNetworkPriority)
    mux.HandleFunc("/api/network/set", SetNetworkPriority)

    // 时间同步模块
    mux.HandleFunc("/api/time/status", GetTimeStatus)
    mux.HandleFunc("/api/time/sync", SyncTime)

    // Fail2ban 模块
    mux.HandleFunc("/api/fail2ban/status", GetFail2banStatus)
    mux.HandleFunc("/api/fail2ban/jails", GetFail2banJails)
    mux.HandleFunc("/api/fail2ban/unban", UnbanIP)

    // 日志模块
    mux.HandleFunc("/api/logs/singbox", GetSingboxLogs)
    mux.HandleFunc("/api/logs/fail2ban", GetFail2banLogs)

    // 证书状态模块
    mux.HandleFunc("/api/cert/status", GetCertStatus)
}

// -------------------- 通用工具 --------------------

func logMiddleware(next http.Handler) http.Handler {
    return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        start := time.Now()
        next.ServeHTTP(w, r)
        fmt.Printf("[%s] %s %s %s\n",
            start.Format("2006-01-02 15:04:05"),
            r.RemoteAddr,
            r.Method,
            r.URL.Path,
        )
    })
}

func writeJSON(w http.ResponseWriter, status int, data interface{}) {
    w.Header().Set("Content-Type", "application/json")
    w.WriteHeader(status)
    _ = json.NewEncoder(w).Encode(data)
}

func writeError(w http.ResponseWriter, status int, msg string) {
    writeJSON(w, status, map[string]interface{}{
        "success": false,
        "error":   msg,
    })
}

// -------------------- Ping --------------------

func PingHandler(w http.ResponseWriter, r *http.Request) {
    writeJSON(w, http.StatusOK, map[string]string{"msg": "pong"})
}

// -------------------- Reality 模块 --------------------

func GetRealityInfo(w http.ResponseWriter, r *http.Request) {
    // TODO: 读取 config.json 并返回 Reality 配置
    writeJSON(w, http.StatusOK, map[string]interface{}{
        "listen_port": 52368,
        "server_name": "www.amd.com",
        "uuid":        "demo-uuid",
        "private_key": "demo-priv",
        "public_key":  "demo-pub",
        "short_id":    "demo-short",
        "flow":        "xtls-rprx-vision",
        "user_name":   "Reality_Default",
    })
}

func UpdateRealityConfig(w http.ResponseWriter, r *http.Request) {
    if r.Method != http.MethodPost {
        writeError(w, http.StatusMethodNotAllowed, "method not allowed")
        return
    }
    // TODO: 解析 JSON，更新 config.json
    writeJSON(w, http.StatusOK, map[string]bool{"success": true})
}

func ResetRealityKeys(w http.ResponseWriter, r *http.Request) {
    if r.Method != http.MethodPost {
        writeError(w, http.StatusMethodNotAllowed, "method not allowed")
        return
    }
    // TODO: 生成新密钥、UUID、short_id，并写入 config.json
    writeJSON(w, http.StatusOK, map[string]string{
        "private_key": "new-priv",
        "public_key":  "new-pub",
        "uuid":        "new-uuid",
        "short_id":    "new-short",
    })
}

func RestartRealityService(w http.ResponseWriter, r *http.Request) {
    if r.Method != http.MethodPost {
        writeError(w, http.StatusMethodNotAllowed, "method not allowed")
        return
    }
    // TODO: 调用 systemctl restart sing-box
    writeJSON(w, http.StatusOK, map[string]bool{"success": true})
}

// -------------------- 流量模块 --------------------

func GetTrafficInfo(w http.ResponseWriter, r *http.Request) {
    // TODO: 读取 traffic.json
    writeJSON(w, http.StatusOK, map[string]interface{}{
        "upload":      0,
        "download":    0,
        "last_update": "",
    })
}

func ResetTraffic(w http.ResponseWriter, r *http.Request) {
    if r.Method != http.MethodPost {
        writeError(w, http.StatusMethodNotAllowed, "method not allowed")
        return
    }
    // TODO: 重置 traffic.json
    writeJSON(w, http.StatusOK, map[string]bool{"success": true})
}

// -------------------- 系统模块 --------------------

func GetSystemInfo(w http.ResponseWriter, r *http.Request) {
    // TODO: 获取时区、swap 信息
    writeJSON(w, http.StatusOK, map[string]interface{}{
        "timezone": "UTC",
        "swap":     0,
    })
}

func SetTimezone(w http.ResponseWriter, r *http.Request) {
    if r.Method != http.MethodPost {
        writeError(w, http.StatusMethodNotAllowed, "method not allowed")
        return
    }
    // TODO: timedatectl set-timezone
    writeJSON(w, http.StatusOK, map[string]bool{"success": true})
}

func SetSwap(w http.ResponseWriter, r *http.Request) {
    if r.Method != http.MethodPost {
        writeError(w, http.StatusMethodNotAllowed, "method not allowed")
        return
    }
    // TODO: 创建/删除 swap
    writeJSON(w, http.StatusOK, map[string]bool{"success": true})
}

// -------------------- 防火墙模块 --------------------

func GetFirewallRules(w http.ResponseWriter, r *http.Request) {
    // TODO: 读取已放行端口
    writeJSON(w, http.StatusOK, map[string]interface{}{
        "ports": []int{22, 52368, 8443},
    })
}

func OpenFirewallPort(w http.ResponseWriter, r *http.Request) {
    if r.Method != http.MethodPost {
        writeError(w, http.StatusMethodNotAllowed, "method not allowed")
        return
    }
    // TODO: 放行端口
    writeJSON(w, http.StatusOK, map[string]bool{"success": true})
}

func CloseFirewallPort(w http.ResponseWriter, r *http.Request) {
    if r.Method != http.MethodPost {
        writeError(w, http.StatusMethodNotAllowed, "method not allowed")
        return
    }
    // TODO: 关闭端口
    writeJSON(w, http.StatusOK, map[string]bool{"success": true})
}

// -------------------- 服务模块 --------------------

func GetServiceStatus(w http.ResponseWriter, r *http.Request) {
    // TODO: systemctl is-active sing-box
    writeJSON(w, http.StatusOK, map[string]string{"status": "running"})
}

func RestartService(w http.ResponseWriter, r *http.Request) {
    if r.Method != http.MethodPost {
        writeError(w, http.StatusMethodNotAllowed, "method not allowed")
        return
    }
    // TODO: systemctl restart sing-box
    writeJSON(w, http.StatusOK, map[string]bool{"success": true})
}

// -------------------- 配置模块 --------------------

func ViewConfig(w http.ResponseWriter, r *http.Request) {
    // TODO: 读取 /opt/reality-panel/config.json
    writeJSON(w, http.StatusOK, map[string]string{"content": "{}"})
}

func SaveConfig(w http.ResponseWriter, r *http.Request) {
    if r.Method != http.MethodPost {
        writeError(w, http.StatusMethodNotAllowed, "method not allowed")
        return
    }
    // TODO: 保存 config.json
    writeJSON(w, http.StatusOK, map[string]bool{"success": true})
}

// -------------------- BBR 模块 --------------------

func GetBBRStatus(w http.ResponseWriter, r *http.Request) {
    // TODO: 检查 sysctl
    writeJSON(w, http.StatusOK, map[string]bool{"enabled": true})
}

func EnableBBR(w http.ResponseWriter, r *http.Request) {
    if r.Method != http.MethodPost {
        writeError(w, http.StatusMethodNotAllowed, "method not allowed")
        return
    }
    // TODO: 写 sysctl.conf + sysctl -p
    writeJSON(w, http.StatusOK, map[string]bool{"success": true})
}

// -------------------- 网络优先级模块 --------------------

func GetNetworkPriority(w http.ResponseWriter, r *http.Request) {
    // TODO: 读取 /etc/gai.conf
    writeJSON(w, http.StatusOK, map[string]string{"mode": "ipv4"})
}

func SetNetworkPriority(w http.ResponseWriter, r *http.Request) {
    if r.Method != http.MethodPost {
        writeError(w, http.StatusMethodNotAllowed, "method not allowed")
        return
    }
    // TODO: 修改 /etc/gai.conf
    writeJSON(w, http.StatusOK, map[string]bool{"success": true})
}

// -------------------- 时间同步模块 --------------------

func GetTimeStatus(w http.ResponseWriter, r *http.Request) {
    // TODO: timedatectl status
    writeJSON(w, http.StatusOK, map[string]interface{}{
        "time":      time.Now().Format("2006-01-02 15:04:05"),
        "timezone":  "UTC",
        "ntp_active": true,
    })
}

func SyncTime(w http.ResponseWriter, r *http.Request) {
    if r.Method != http.MethodPost {
        writeError(w, http.StatusMethodNotAllowed, "method not allowed")
        return
    }
    // TODO: 手动同步时间
    writeJSON(w, http.StatusOK, map[string]bool{"success": true})
}

// -------------------- Fail2ban 模块 --------------------

func GetFail2banStatus(w http.ResponseWriter, r *http.Request) {
    // TODO: fail2ban-client status
    writeJSON(w, http.StatusOK, map[string]string{"status": "running"})
}

func GetFail2banJails(w http.ResponseWriter, r *http.Request) {
    // TODO: fail2ban-client status
    writeJSON(w, http.StatusOK, map[string][]string{"jails": {"sshd", "nginx-http-auth"}})
}

func UnbanIP(w http.ResponseWriter, r *http.Request) {
    if r.Method != http.MethodPost {
        writeError(w, http.StatusMethodNotAllowed, "method not allowed")
        return
    }
    // TODO: fail2ban-client set <jail> unbanip <ip>
    writeJSON(w, http.StatusOK, map[string]bool{"success": true})
}

// -------------------- 日志模块 --------------------

func GetSingboxLogs(w http.ResponseWriter, r *http.Request) {
    // TODO: 读取 sing-box 日志
    writeJSON(w, http.StatusOK, map[string][]string{"lines": {}})
}

func GetFail2banLogs(w http.ResponseWriter, r *http.Request) {
    // TODO: 读取 fail2ban 日志
    writeJSON(w, http.StatusOK, map[string][]string{"lines": {}})
}

// -------------------- 证书状态模块 --------------------

func GetCertStatus(w http.ResponseWriter, r *http.Request) {
    // TODO: 解析 panel.crt，返回颁发者、有效期、剩余天数等
    writeJSON(w, http.StatusOK, map[string]interface{}{
        "issuer":         "ZeroSSL",
        "valid_from":     "",
        "valid_to":       "",
        "days_remaining": 0,
        "ip":             "",
    })
}
