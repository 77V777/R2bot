# iPhone 相机自动上传示例（SwiftUI）

说明：
这个示例实现了一个 iOS SwiftUI 应用，它在应用内调起相机拍照，拍完照片后会自动向你的后端请求 presigned URL，并把照片 PUT 上传到 Cloudflare R2。该示例适用于你已经在本地运行 `server`（presign server）的情况。

先决条件：
- 在桌面启动过 `r2-autoupload/server`，并且已正确填写 `server/.env`，服务可通过 HTTPS 或 HTTP 访问（生产请用 HTTPS）。
- Xcode 14+（或兼容版本）

如何使用：
1. 在 Xcode 创建一个新的 SwiftUI App（iOS，生命周期 SwiftUI）。
2. 把 `R2CameraUploadApp.swift`、`ContentView.swift`、`ImagePicker.swift`、`NetworkManager.swift` 替换到项目内（或直接把本目录作为 Swift Package 导入）。
3. 在 `Info.plist` 中添加键：
   - `NSCameraUsageDescription`（相机权限说明）
   - `NSPhotoLibraryAddUsageDescription`（如需保存到相册）
   - 如果你的 presign server 在本地使用 `http://`，在 `Info.plist` 添加 App Transport Security 例外或使用 ngrok 的 `https` 地址。
4. 在 `NetworkManager.swift` 内把 `PRESIGN_SERVER` 改为你的后端地址，例如 `https://xxxx.ngrok.io` 或 `https://yourdomain.com`。
5. 运行到真机（模拟器没有相机或有限制），点击“拍照并上传”，拍摄后会自动上传并在屏幕显示结果。

注意：
- 这个示例是“应用内拍照并上传”。如果你希望监视系统相机拍摄后自动上传（即监控 iPhone 原生相机 app 的照片），那需要请求照片库权限并实现后台上传策略，受 iOS 限制且更加复杂；我可以据此为你另写说明。

需要我继续做什么：
- 我可以把这个示例打包成完整 Xcode 项目并尝试构建（需要你允许我在桌面创建更多文件）。
- 或者我可以实现“监控照片库并自动上传新照片”的功能（将说明所需权限与限制）。