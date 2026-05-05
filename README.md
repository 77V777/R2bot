# r2-autoupload

项目概述
-- 这是一个示例项目，演示如何使用后端生成 presigned URL，让移动端或脚本直接将照片/文件上传到 Cloudflare R2。后端仅负责签名与列举对象，实际对象由客户端直接 PUT 到 R2。包含：
- `server/`：Node.js presign 服务（`/get-presigned-url`, `/get-presigned-get`, `/list-objects`）。
- `flutter-client/`：Flutter 示例，拍照并上传到 R2（带进度与重试）。
- `ios-client-xcode/`：iOS SwiftUI 示例（PhotoMonitor、持久化上传队列、BGTaskScheduler 支持）。
- `scripts/`：实用脚本，包括 `presign_uploader.py`（批量并行上传 CLI）和 `upload_to_presign.py`（简单单文件上传脚本）。

快速开始
1. 克隆到本机并进入目录：

```bash
git clone <your-repo-url>
cd r2-autoupload
```

2. 配置后端：在 `server/.env` 中填入你的 R2 凭证与 bucket：

```
R2_ACCOUNT_ID=your_account_id
R2_ACCESS_KEY_ID=xxxx
R2_SECRET_ACCESS_KEY=yyyy
R2_BUCKET=your_bucket
```

3. 启动 presign server（Node.js >=16 推荐，已测试 Node v20）：

```bash
cd server
npm install
npm start
# 监听在 3000
```

4. 上传测试（Python 脚本）：

```bash
python scripts/upload_to_presign.py C:\path\to\file.jpg
```

或使用批量 CLI：

```bash
python scripts/presign_uploader.py --dir ./to_upload --concurrency 4 --get-download-links --expires 3600
```

Flutter 客户端
- 在 `flutter-client/lib/main.dart` 修改 `presignServer` 指向你的 presign server（如果手机不能访问 `localhost`，使用 ngrok 或服务器公网地址）。
- 运行：

```bash
cd flutter-client
flutter pub get
flutter run
```

iOS 客户端
- 打开 `ios-client-xcode` 工程到 Xcode（需 macOS）。
- 在 `Signing & Capabilities` 中打开 Background Modes -> Background fetch，并确保 `Info.plist` 中有 `BGTaskSchedulerPermittedIdentifiers`。

文档与脚本
- `scripts/presign_uploader.py`：并行批量上传 CLI（依赖 `requests`）。
- `scripts/upload_to_presign.py`：单文件上传脚本（依赖 `requests`）。

安全建议
- presign 链接有效期应尽量短（按需延长），并在可能时通过后端做访问控制或记录。不要把长期有效的凭证硬编码到客户端。

许可证
- 请根据需要添加 LICENSE 文件。
# Cloudflare R2 自动上传示例

这个示例包含：

- `server/`：Node.js 后端，用于生成 Cloudflare R2 的 presigned URL（PUT）。
- `client/`：Python 脚本，自动读取桌面上的 `img211.jpg`（示例），请求 presigned URL 并上传到 R2。

目标：在你提供 R2 的 `ACCESS_KEY` / `SECRET` 和 `ACCOUNT_ID` 后，能“一键”在本地运行并自动把照片上传到 R2。

快速开始

1. 填写后端环境变量：复制 `server/.env.example` 为 `server/.env` 并填写你的 R2 信息。
2. 安装后端依赖并启动：

```bash
cd C:\Users\Administrator\Desktop\r2-autoupload\server
npm install
npm start
```

3. 在另一个终端运行客户端自动上传脚本（会读取桌面 `img211.jpg`）：

```bash
cd C:\Users\Administrator\Desktop\r2-autoupload\client
python upload.py
```

如果需要在手机真实拍照上传，请告诉我，我会为你生成 Flutter 项目样例。