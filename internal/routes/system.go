package routes

import (
    "net/http"

    "init-panel/internal/core"
    "init-panel/internal/utils"
)

func registerSystemRoutes(mux *http.ServeMux) {
    mux.HandleFunc("/api/system/info", handleSystemInfo)
}

func handleSystemInfo(w http.ResponseWriter, r *http.Request) {
    if r.Method != http.MethodGet {
        utils.Error(w, http.StatusMethodNotAllowed, "method not allowed")
        return
    }
    info, err := core.GetSystemInfo()
    if err != nil {
        utils.Error(w, http.StatusInternalServerError, err.Error())
        return
    }
    utils.JSON(w, http.StatusOK, info)
}
