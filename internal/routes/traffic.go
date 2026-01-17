package routes

import (
    "net/http"

    "init-panel/internal/core"
    "init-panel/internal/utils"
)

func registerTrafficRoutes(mux *http.ServeMux) {
    mux.HandleFunc("/api/traffic/summary", handleTrafficSummary)
}

func handleTrafficSummary(w http.ResponseWriter, r *http.Request) {
    if r.Method != http.MethodGet {
        utils.Error(w, http.StatusMethodNotAllowed, "method not allowed")
        return
    }
    data, err := core.GetTrafficSummary()
    if err != nil {
        utils.Error(w, http.StatusInternalServerError, err.Error())
        return
    }
    utils.JSON(w, http.StatusOK, data)
}
