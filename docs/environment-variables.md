# 环境变量清单

下表汇总 `scripts/deploy_streamserve.sh` 与相关部署流程所需的环境变量，建议在部署主机的 `.env` 文件或 CI/CD 密钥仓中统一维护，并通过 `docker compose --env-file` 加载。

| 变量 | 说明 | 配置方式 | 示例值 |
| --- | --- | --- | --- |
| `STREAMSERVE_DOMAIN` | 公网访问域名，用于配置 nginx server_name 与 HLS URL。 | 在 `.env` 中设置或通过 `export STREAMSERVE_DOMAIN=<域名>` 注入后再运行部署脚本。 | `stream.example.com` |
| `SSL_CERT_PATH` | 同时包含证书链与私钥的 PEM 文件路径，供 nginx HTTPS 监听使用。 | 将 PEM 文件挂载至容器并在 `.env` 中写入绝对路径（证书与私钥可放于同一文件）。 | `/etc/ssl/certs/streamserve.pem` |
| `PUSH_KEY` | 推流鉴权密钥，用于生成 RTMP 推流签名或查询参数。 | 通过秘密管理服务下发，部署前写入 `.env` 或 CI 变量，避免明文保存。 | `s3cr3tpushkey` |
| `RTMP_ALLOWED_IPS` | 允许的推流来源 IP 列表，用于控制访问白名单。 | 在 `.env` 中以逗号分隔列出；Shell 中可使用 `export RTMP_ALLOWED_IPS="1.2.3.4,5.6.7.8"`。 | `203.0.113.10,198.51.100.25` |

> **提示**：如需在 Shell 会话中临时设置，可使用 `export <变量>=<值>`；在 systemd 服务或 CI 任务中，请以密钥存储方式注入，避免写入仓库。
