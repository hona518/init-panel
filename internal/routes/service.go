package routes

import (
    "net/http"

    "init-panel/internal/core"
    "init-panel/internal/utils"
)

func registerServiceRoutes(mux *http.ServeMux) {
    mux.HandleFunc("/api/service/restart", handleServiceRestart)
    mux.HandleFunc("/api/service/status", handleServiceStatus)
}

func handleServiceRestart(w http.ResponseWriter, r *http.Request) {
    if r.Method != http.MethodPost {
        utils.Error(w, http.StatusMethodNotAllowed, "method not allowed")
        return
    }
    service := r.URL.Query().Get("name")
    if service == "" {
        utils.Error(w, http.StatusBadRequest, "missing service name")
        return
    }
    if err := core.RestartService(service); err != nil {
        utils.Error(w, http.StatusInternalServerError, err.Error())
        return
    }
    utils.JSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

func handleServiceStatus(w http.ResponseWriter, r *http.Request) {
    if r.Method != http.MethodGet {
        utils.Error(w, http.StatusMethodNotAllowed, "method not allowed")
        return
    }
    service := r.URL.Query().Get("name")
    if service == "" {
        utils.Error(w, http.StatusBadRequest, "missing service name")
        return
    }
    status, err := core.GetServiceStatus(service)
    if err != nil {
        utils.Error(w, http.StatusInternalServerError, err.Error())
        return
    }
    utils.JSON(w, http.StatusOK, status)
}
