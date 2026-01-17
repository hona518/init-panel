package core

import (
    "strings"

    "init-panel/internal/utils"
)

type ServiceStatus struct {
    Name   string `json:"name"`
    Active bool   `json:"active"`
    Raw    string `json:"raw"`
}

func RestartService(name string) error {
    _, err := utils.RunCommand("systemctl", "restart", name)
    return err
}

func GetServiceStatus(name string) (*ServiceStatus, error) {
    out, err := utils.RunCommand("systemctl", "is-active", name)
    if err != nil {
        return &ServiceStatus{
            Name:   name,
            Active: false,
            Raw:    out,
        }, nil
    }
    active := strings.TrimSpace(out) == "active"
    return &ServiceStatus{
        Name:   name,
        Active: active,
        Raw:    strings.TrimSpace(out),
    }, nil
}
