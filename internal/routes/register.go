package routes

import "net/http"

func RegisterAll(mux *http.ServeMux) {
    registerSystemRoutes(mux)
    registerServiceRoutes(mux)
    registerLogsRoutes(mux)
    registerTrafficRoutes(mux)
    registerFirewallRoutes(mux)
    registerRealityRoutes(mux)
}
