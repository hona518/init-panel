package utils

import (
    "bytes"
    "os/exec"
    "strings"
)

func RunCommand(name string, args ...string) (string, error) {
    cmd := exec.Command(name, args...)
    var out bytes.Buffer
    var stderr bytes.Buffer
    cmd.Stdout = &out
    cmd.Stderr = &stderr
    err := cmd.Run()
    if err != nil {
        return stderr.String(), err
    }
    return out.String(), nil
}

func RunCommandLines(name string, args ...string) ([]string, error) {
    out, err := RunCommand(name, args...)
    if err != nil {
        return nil, err
    }
    lines := strings.Split(strings.TrimSpace(out), "\n")
    return lines, nil
}
