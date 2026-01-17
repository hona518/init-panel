package core

type TrafficSummary struct {
    InboundBytes  uint64 `json:"inbound_bytes"`
    OutboundBytes uint64 `json:"outbound_bytes"`
}

func GetTrafficSummary() (*TrafficSummary, error) {
    // TODO: 从 Reality / Xray / sing-box 统计接口获取真实数据
    return &TrafficSummary{
        InboundBytes:  0,
        OutboundBytes: 0,
    }, nil
}
