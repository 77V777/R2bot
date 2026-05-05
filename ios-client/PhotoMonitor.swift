import Foundation
import Photos
import UIKit

/// PhotoMonitor：监控照片库变化并将新拍摄的照片自动上传到 presign server -> R2
/// 注意：iOS 不允许持续后台常驻监听，真实“拍完就立刻上传”只在 App 在前台或系统授予后台执行时间时能实时执行。
/// 本实现：
/// - 在 App 启动时请求 Photos 访问权限并注册 `PHPhotoLibraryChangeObserver`。
/// - 维护上次处理的 asset localIdentifier（保存在 UserDefaults）。
/// - 当检测到变化时，拉取最近的照片并对未处理的照片执行上传逻辑。
/// - 适配在前台即时工作；在后台尽力通过 `BGAppRefreshTask` / Background Fetch 被唤醒时运行一次检查（需在 Xcode 开启 Background Modes）。

class PhotoMonitor: NSObject, PHPhotoLibraryChangeObserver {
    static let shared = PhotoMonitor()
    private let userDefaultsKey = "PhotoMonitor.lastProcessed"
    private let serialQueue = DispatchQueue(label: "PhotoMonitor.queue")

    private override init() {
        super.init()
    }

    func start() {
        // 请求读取权限（iOS 14+ 推荐 readWrite）
        if #available(iOS 14, *) {
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                DispatchQueue.main.async {
                    self.handleAuth(status: status)
                }
            }
        } else {
            PHPhotoLibrary.requestAuthorization { status in
                DispatchQueue.main.async {
                    self.handleAuth(status: status)
                }
            }
        }
    }

    private func handleAuth(status: PHAuthorizationStatus) {
        switch status {
        case .authorized, .limited, .ephemeral:
            PHPhotoLibrary.shared().register(self)
            // 初始化 last processed（如果为空则记录当前最新一张，避免批量回传历史照片）
            if self.getLastProcessed() == nil {
                self.recordCurrentLatestAsset()
            }
        default:
            // 无权限，应用应提示用户开启权限
            break
        }
    }

    func stop() {
        PHPhotoLibrary.shared().unregisterChangeObserver(self)
    }

    func photoLibraryDidChange(_ changeInstance: PHChange) {
        // 触发时可能在后台线程，切回主队列再处理
        DispatchQueue.main.async {
            self.serialQueue.async {
                self.checkForNewPhotos()
            }
        }
    }

    // 立即检查并上传未处理的新照片（可被后台任务调用）
    func checkForNewPhotos() {
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        fetchOptions.fetchLimit = 10
        let assets = PHAsset.fetchAssets(with: .image, options: fetchOptions)
        guard assets.count > 0 else { return }

        var toProcess: [PHAsset] = []
        let lastId = getLastProcessed()

        assets.enumerateObjects { (asset, idx, stop) in
            if let last = lastId {
                if asset.localIdentifier == last {
                    stop.pointee = true
                    return
                }
                toProcess.append(asset)
            } else {
                // 如果之前没有记录，默认不处理历史照片（只记录当前最新）
                toProcess = []
                stop.pointee = true
            }
        }

        // 处理数组顺序：从最旧到最新上传（反转）
        toProcess.reverse()
        for asset in toProcess {
            // 下载 image data 并入队列，由 UploadQueue 负责上传/重试
            requestImageData(for: asset) { data in
                if let data = data {
                    UploadQueue.shared.enqueue(data: data, id: asset.localIdentifier)
                }
            }
        }

        // 若之前没有记录，记录当前第一张
        if lastId == nil, let first = assets.firstObject {
            setLastProcessed(id: first.localIdentifier)
        }
    }

    private func requestImageData(for asset: PHAsset, completion: @escaping (Data?) -> Void) {
        let options = PHImageRequestOptions()
        options.isSynchronous = false
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true

        if #available(iOS 13, *) {
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, dataUTI, orientation, info in
                completion(data)
            }
        } else {
            PHImageManager.default().requestImageData(for: asset, options: options) { data, dataUTI, orientation in
                completion(data)
            }
        }
    }

    private func uploadImageData(_ data: Data, completion: @escaping (Bool) -> Void) {
        // 使用项目内的 NetworkManager 获取 presign URL 并上传（它在 ios-client 中已有）
        let contentType = "image/jpeg"
        Task {
            // 带重试的上传实现（指数退避，最多 3 次）
            let maxAttempts = 3
            var attempt = 0
            var success = false
            while attempt < maxAttempts && !success {
                attempt += 1
                do {
                    let presign = try await NetworkManager.getPresignedURL(contentType: contentType, ext: "jpg")
                    guard let url = URL(string: presign.url) else { break }

                    var req = URLRequest(url: url)
                    req.httpMethod = "PUT"
                    req.setValue(contentType, forHTTPHeaderField: "Content-Type")
                    let (_, resp) = try await URLSession.shared.upload(for: req, from: data)
                    if let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                        success = true
                        // 发送本地通知告知上传成功
                        sendLocalNotification(title: "上传成功", body: presign.key)
                        completion(true)
                        break
                    } else {
                        // 失败，抛出以触发重试
                        throw NetworkError.serverError("HTTP \((resp as? HTTPURLResponse)?.statusCode ?? -1)")
                    }
                } catch {
                    // 失败处理：在最后一次失败时发送通知
                    if attempt >= maxAttempts {
                        sendLocalNotification(title: "上传失败", body: "尝试 \(attempt) 次后失败")
                        completion(false)
                        break
                    }
                    // 指数退避
                    let wait = UInt32(pow(2.0, Double(attempt)))
                    sleep(wait)
                }
            }
        }
    }

    // 本地通知（需要在 App 启动时请求通知权限）
    private func sendLocalNotification(title: String, body: String) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            if settings.authorizationStatus != .authorized {
                center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                    if granted {
                        self.postNotification(title: title, body: body)
                    }
                }
            } else {
                self.postNotification(title: title, body: body)
            }
        }
    }

    private func postNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    // MARK: - last processed id helpers
    private func getLastProcessed() -> String? {
        return UserDefaults.standard.string(forKey: userDefaultsKey)
    }
    private func setLastProcessed(id: String) {
        UserDefaults.standard.set(id, forKey: userDefaultsKey)
    }

    // 记录当前最新一张 asset（用于首次安装时避免上传历史照片）
    private func recordCurrentLatestAsset() {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.fetchLimit = 1
        let assets = PHAsset.fetchAssets(with: .image, options: options)
        if let first = assets.firstObject {
            setLastProcessed(id: first.localIdentifier)
        }
    }
}

