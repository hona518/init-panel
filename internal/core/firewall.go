package core

type FirewallRule struct {
    Raw string `json:"raw"`
}

func ListFirewallRules() ([]FirewallRule, error) {
    // TODO: 这里可以用 iptables-save / nft list ruleset 等方式实现
    return []FirewallRule{}, nil
}
