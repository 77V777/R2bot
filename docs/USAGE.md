# 使用说明（Detailed Usage）

本文件补充 `README.md` 中的快速开始，提供更详细的运行与测试步骤。

1) 启动后端 presign server

```bash
cd server
npm install
# 编辑 .env 并确保 R2 凭证与 bucket 正确
npm start
```

2) 上传文件（单文件）

```bash
python scripts/upload_to_presign.py C:\Users\Administrator\Desktop\1111.jpg
```

3) 批量并行上传（CLI）

```bash
python scripts/presign_uploader.py --dir C:\path\to\to_upload --concurrency 6 --get-download-links --expires 3600 --output results.csv
```

说明：`--expires` 参数由后端限制最大值（当前实现最大 604800 秒，即 7 天）。

4) 获取 presigned GET 链接并下载

在上传并获得 `key` 后，可以调用：

```
GET /get-presigned-get?key=<key>&expires=<seconds>
```

示例：

```bash
curl -L -o file.zip "http://localhost:3000/get-presigned-get?key=...&expires=3600"
```

5) 常见问题
- 如果手机无法访问 `http://localhost:3000`，请使用 `ngrok http 3000` 或把后端部署到云服务器。
- 在 iOS 上，后台任务受系统调度限制，BGTask 不能保证严格按计划运行，需搭配持久化上传队列与失效重试策略。
