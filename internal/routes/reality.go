package routes

import (
    "net/http"

    "init-panel/internal/core"
    "init-panel/internal/utils"
)

func registerRealityRoutes(mux *http.ServeMux) {
    mux.HandleFunc("/api/reality/config", handleRealityConfig)
}

func handleRealityConfig(w http.ResponseWriter, r *http.Request) {
    switch r.Method {
    case http.MethodGet:
        cfg, err := core.GetRealityConfig()
        if err != nil {
            utils.Error(w, http.StatusInternalServerError, err.Error())
            return
        }
        utils.JSON(w, http.StatusOK, cfg)
    default:
        utils.Error(w, http.StatusMethodNotAllowed, "method not allowed")
    }
}
