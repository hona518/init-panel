package core

import "init-panel/internal/utils"

func GetSystemdLogs(service string, limit int) ([]string, error) {
    args := []string{"-u", service, "-n", "200", "--no-pager"}
    return utils.RunCommandLines("journalctl", args...)
}
