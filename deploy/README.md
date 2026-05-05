部署与一键测试说明

目标：把后端长期运行并在公网可访问（用于手机或远程测试）。下面提供两种常见方式：本机 + ngrok（快速外网临时访问）和使用 `pm2` 在服务器上后台运行。

1) 使用 ngrok（快速，适合调试）
- 下载并安装 ngrok（https://ngrok.com/）并登录
- 暴露本地 3000 端口：

```powershell
ngrok http 3000
```

- 拿到生成的 https 地址（例如 `https://abcd-1234.ngrok.io`），在 `ios-client/NetworkManager.swift` 中把 `PRESIGN_SERVER` 改为该 https 地址，并在手机上使用该地址进行测试。

2) 使用 pm2 在 Linux/Windows 上持久化运行（建议生产选 Linux）
- 安装 pm2（需要 Node 环境）：

```bash
npm install -g pm2
pm install
pm run start
pm2 start index.js --name r2-presign-server --cwd C:/Users/Administrator/Desktop/r2-autoupload/server
pm2 save
```

- 查看日志：

```bash
pm2 logs r2-presign-server
```

3) 自动化脚本（Windows）
- 提示：你可以在 Windows 上创建一个 `start-server.bat` 内容如下：

```bat
cd /d C:\Users\Administrator\Desktop\r2-autoupload\server
npm install
node index.js
```

4) 安全建议
- 不要在公网上暴露永久密钥。建议仅在可信网络或通过短期隧道（如 ngrok）测试。
- 如需公网长期部署，建议部署到受控主机并使用环境变量注入密钥，且限制服务请求（添加认证、速率限制）。

我可以按需为你生成 `pm2` ecosystem 文件或 `start-server.bat`。