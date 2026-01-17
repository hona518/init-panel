package routes

import (
    "net/http"

    "init-panel/internal/core"
    "init-panel/internal/utils"
)

func registerFirewallRoutes(mux *http.ServeMux) {
    mux.HandleFunc("/api/firewall/rules", handleFirewallRules)
}

func handleFirewallRules(w http.ResponseWriter, r *http.Request) {
    if r.Method != http.MethodGet {
        utils.Error(w, http.StatusMethodNotAllowed, "method not allowed")
        return
    }
    rules, err := core.ListFirewallRules()
    if err != nil {
        utils.Error(w, http.StatusInternalServerError, err.Error())
        return
    }
    utils.JSON(w, http.StatusOK, rules)
}
