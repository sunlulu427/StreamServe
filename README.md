# StreamServe

StreamServe 是基于 `nginx` 与 `nginx-rtmp-module` 的直播推流参考实现，
提供容器化部署、自动化脚本与环境变量模板，帮助在云服务器上快速
搭建可支持 RTMP 推流与 HLS 播放的流媒体服务。

## 环境准备

- Ubuntu 22.04 LTS（或兼容发行版），具备外网访问与开放的 22/80/443/1935
  端口。
- 拥有 `sudo` 权限的运维账号，可通过堡垒机或直接 SSH 连接。
- 已申请的公网域名及对应 SSL 证书（PEM，含私钥）。
- Git 与 Docker Hub 的访问权限（若使用私有镜像需提前登录）。

### Git 访问配置

若在远程服务器克隆仓库时遇到 `Permission denied (publickey)` 错误，按
以下步骤处理：

1. 生成 SSH 密钥（如果尚未生成）：
   ```bash
   ssh-keygen -t ed25519 -C "your_email@example.com"
   # 或使用 RSA: ssh-keygen -t rsa -b 4096 -C "your_email@example.com"
   ```
   按提示保存在 `~/.ssh/id_ed25519`（或 `id_rsa`）。

2. 上传公钥到 Git 托管平台：
   ```bash
   cat ~/.ssh/id_ed25519.pub
   ```
   将输出内容复制到 GitHub/GitLab 的 **SSH Keys** 管理界面。

3. 配置 Git 用户信息并测试连接：
   ```bash
   git config --global user.name "Your Name"
   git config --global user.email "your_email@example.com"
   ssh -T git@github.com   # GitLab 则为 git@gitlab.com
   ```

4. 如环境无法使用 SSH，可改用 HTTPS 并使用个人访问令牌（PAT）：
   ```bash
   git clone https://github.com/<your-org>/streamserve.git
   ```
   首次 push 时输入 PAT 作为密码。

## 部署步骤

按顺序执行以下操作，可在目标云主机上完成端到端部署：

1. **SSH 登录服务器**
   ```bash
   ssh -J <bastion_user>@<bastion_host> <user>@<target_host>
   ```

2. **更新系统补丁并安装基础工具**
   - 对于 Debian/Ubuntu：
     ```bash
     sudo apt-get update -y
     sudo apt-get upgrade -y
     sudo apt-get install -y ca-certificates curl git gnupg lsb-release
     ```
   - 对于 RHEL/CentOS/Amazon Linux：
     ```bash
     sudo yum update -y
     sudo yum install -y ca-certificates curl git gnupg2 tar
     ```

3. **安装 Docker Engine 与 Docker Compose 插件**
   - 对于 Debian/Ubuntu：
     ```bash
     sudo install -m 0755 -d /etc/apt/keyrings
     curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
       | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
     echo \
   "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
   https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
       | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
     sudo apt-get update -y
     sudo apt-get install -y docker-ce docker-ce-cli containerd.io \
       docker-buildx-plugin docker-compose-plugin
     ```
   - 对于 RHEL/CentOS/Amazon Linux：
     ```bash
     sudo yum install -y yum-utils
     sudo yum-config-manager \
       --add-repo https://download.docker.com/linux/centos/docker-ce.repo
     sudo yum install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin \
       docker-compose-plugin
     ```
   安装完成后均需启动并设为开机自启：
   ```bash
   sudo systemctl enable docker
   sudo systemctl start docker
   ```
   成功后可通过 `docker version`、`docker compose version`（或
   `docker-compose version`）确认安装结果。

> **镜像源与常见故障排查**
>
> - 若访问 `download.docker.com` 失败（常见报错 `SSL_ERROR_SYSCALL` 或无法
>   下载 `repomd.xml`），可替换为阿里云镜像：
>   ```bash
>   sudo tee /etc/yum.repos.d/docker-ce.repo >/dev/null <<'EOF'
>   [docker-ce-stable]
>   name=Docker CE Stable - $basearch
>   baseurl=https://mirrors.aliyun.com/docker-ce/linux/centos/8/$basearch/stable
>   enabled=1
>   gpgcheck=1
>   gpgkey=https://mirrors.aliyun.com/docker-ce/linux/centos/gpg
>   EOF
>   sudo yum makecache
>   sudo yum install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin \
>     docker-compose-plugin
>   ```
> - 确保系统时间准确并更新证书仓：`sudo timedatectl set-ntp true`、
>   `sudo yum install -y ca-certificates`。
> - 如仓库仅能安装 `docker-compose-plugin` 而缺少 Docker Engine，请先移除
>   再执行上述完整安装命令，直至 `rpm -ql docker-ce | grep docker.service`
>   能输出服务文件。

4. **克隆仓库并进入目录**
   ```bash
   git clone https://github.com/<your-org>/streamserve.git /opt/streamserve
   cd /opt/streamserve
   ```
   若需从当前目录部署，可在 `scripts/deploy_streamserve.sh` 中通过环境
   变量 `REPO_URL`、`TARGET_DIR` 自定义拉取位置。

5. **准备环境变量**
   ```bash
   sudo cp .env.example /opt/streamserve/.env
   sudo chmod 600 /opt/streamserve/.env
   sudo nano /opt/streamserve/.env
   ```
   根据 `docs/environment-variables.md` 填写 `STREAMSERVE_DOMAIN`、
   `SSL_CERT_PATH`、`PUSH_KEY` 与 `RTMP_ALLOWED_IPS` 等变量。将证书 PEM
   上传至主机后，确保路径与 `.env` 中配置一致。

6. **运行自动化部署脚本**
   ```bash
   sudo ./scripts/deploy_streamserve.sh
   ```
   脚本将完成以下任务：
   - 安装/校验 Docker 与基础依赖。
   - 克隆或更新仓库，并加载 `.env`。
   - 使用 `envsubst` 渲染 `nginx/nginx.conf.tpl` 与
     `nginx/conf.d/rtmp.conf.tpl`。
   - 根据 `RTMP_ALLOWED_IPS` 生成 `nginx/conf.d/rtmp-allow.conf` 白名单。
   - 通过 UFW 或 firewalld 开放 80/443/1935 端口。
   - 执行 `docker compose --env-file .env up -d streamserve`（如环境仅提供
     `docker-compose`，则改用 `docker-compose --env-file .env up -d streamserve`）拉起服务。

7. **验证运行状态**
   ```bash
   docker compose ps streamserve
   docker compose logs -f streamserve
   docker compose exec -T streamserve nginx -t
   ```
   若使用 `docker-compose`，可替换以上命令的前缀。
   成功后，可访问 `http://<STREAMSERVE_DOMAIN>/stat` 查看 RTMP 状态页面，
   HLS 流位于 `http://<STREAMSERVE_DOMAIN>/hls/<stream>.m3u8`。

## 推流与验证

推流端示例：
```bash
ffmpeg -re -i demo.mp4 -c copy -f flv \
  "rtmp://<STREAMSERVE_DOMAIN>/live/stream?key=${PUSH_KEY}"
```

播放验证：
```bash
ffprobe "http://<STREAMSERVE_DOMAIN>/hls/stream.m3u8"
```

## RTMP 模块配置概览

- `nginx/conf.d/rtmp.conf.tpl` 定义了 `listen 1935`、`application live`、
  `hls_path /var/www/hls` 等核心设置，并引入自动生成的推流 IP 白名单。
- `nginx/nginx.conf.tpl` 负责加载 RTMP 配置、暴露 HTTP/HLS 入口以及状态
  页面，HTTPS 监听复用 `.env` 中的证书路径。

如需自定义，修改对应模板后再次运行部署脚本或执行
`docker compose exec streamserve nginx -t && docker compose restart streamserve`
即可。

## 常用运维操作

- **热重载配置**：`./scripts/reload.sh`
- **打包配置**：`./scripts/package.sh`
- **回滚/下线**：`docker compose down --volumes`
- **日志追踪**：`docker compose logs -f streamserve`

若使用 `docker-compose`，可按需替换命令前缀。

更多细节请参考 `AGENTS.md` 与 `docs/environment-variables.md`。
