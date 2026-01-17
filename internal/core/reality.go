package core

type RealityConfig struct {
    Listen   string `json:"listen"`
    Port     int    `json:"port"`
    PrivateKey string `json:"private_key"`
    PublicKey  string `json:"public_key"`
    ShortID    string `json:"short_id"`
    // TODO: 继续补充你 Reality 的字段
}

func GetRealityConfig() (*RealityConfig, error) {
    // TODO: 从 Reality / Xray / sing-box 配置文件读取
    return &RealityConfig{}, nil
}
