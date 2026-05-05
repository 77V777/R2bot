Flutter 客户端示例

说明：这是一个最小 Flutter 应用，拍照并通过后端生成的 presigned URL 上传到 Cloudflare R2。

使用：
1. 安装 Flutter SDK 并在本机配置好 iOS/Android 工具链。
2. 在 `lib/main.dart` 中把 `presignServer` 修改为你的 presign server 地址（例如 https://xxxx.ngrok.io 或 http://192.168.x.y:3000）。
3. 运行：

```bash
cd flutter-client
flutter pub get
flutter run # 在连接的设备上
```

依赖：
- `image_picker`：用于拍照
- `http`：用于请求 presigned URL 与上传
 - `http`：用于请求 presigned URL 与上传
 - `dio`：用于带进度的上传请求
 - `mime`：自动检测文件 mime-type

注意：测试 iOS 真机时，确保 presign server 可从手机访问（使用 ngrok 或部署到公网）。