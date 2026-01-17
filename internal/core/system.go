package core

import (
    "os"
    "runtime"
    "time"
)

type SystemInfo struct {
    Hostname string  `json:"hostname"`
    OS       string  `json:"os"`
    Arch     string  `json:"arch"`
    CPUs     int     `json:"cpus"`
    Uptime   float64 `json:"uptime_seconds"`
}

var startTime = time.Now()

func GetSystemInfo() (*SystemInfo, error) {
    host, _ := os.Hostname()
    return &SystemInfo{
        Hostname: host,
        OS:       runtime.GOOS,
        Arch:     runtime.GOARCH,
        CPUs:     runtime.NumCPU(),
        Uptime:   time.Since(startTime).Seconds(),
    }, nil
}
