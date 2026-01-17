package routes

import (
    "net/http"

    "init-panel/internal/core"
    "init-panel/internal/utils"
)

func registerLogsRoutes(mux *http.ServeMux) {
    mux.HandleFunc("/api/logs/systemd", handleSystemdLogs)
}

func handleSystemdLogs(w http.ResponseWriter, r *http.Request) {
    if r.Method != http.MethodGet {
        utils.Error(w, http.StatusMethodNotAllowed, "method not allowed")
        return
    }
    service := r.URL.Query().Get("name")
    if service == "" {
        utils.Error(w, http.StatusBadRequest, "missing service name")
        return
    }
    lines, err := core.GetSystemdLogs(service, 200)
    if err != nil {
        utils.Error(w, http.StatusInternalServerError, err.Error())
        return
    }
    utils.JSON(w, http.StatusOK, map[string]interface{}{
        "service": service,
        "lines":   lines,
    })
}
