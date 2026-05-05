import Foundation
import Photos
import UIKit

class PhotoMonitor: NSObject, PHPhotoLibraryChangeObserver {
    static let shared = PhotoMonitor()
    private let userDefaultsKey = "PhotoMonitor.lastProcessed"
    private let serialQueue = DispatchQueue(label: "PhotoMonitor.queue")

    private override init() { super.init() }

    func start() {
        if #available(iOS 14, *) {
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                DispatchQueue.main.async { self.handleAuth(status: status) }
            }
        } else {
            PHPhotoLibrary.requestAuthorization { status in
                DispatchQueue.main.async { self.handleAuth(status: status) }
            }
        }
    }

    private func handleAuth(status: PHAuthorizationStatus) {
        switch status {
        case .authorized, .limited, .ephemeral:
            PHPhotoLibrary.shared().register(self)
            if self.getLastProcessed() == nil { self.recordCurrentLatestAsset() }
        default: break
        }
    }

    func stop() { PHPhotoLibrary.shared().unregisterChangeObserver(self) }

    func photoLibraryDidChange(_ changeInstance: PHChange) {
        DispatchQueue.main.async { self.serialQueue.async { self.checkForNewPhotos() } }
    }

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
                if asset.localIdentifier == last { stop.pointee = true; return }
                toProcess.append(asset)
            } else {
                toProcess = []; stop.pointee = true
            }
        }

        toProcess.reverse()
        for asset in toProcess {
            requestImageData(for: asset) { data in
                if let data = data { UploadQueue.shared.enqueue(data: data, id: asset.localIdentifier) }
            }
        }

        if lastId == nil, let first = assets.firstObject { setLastProcessed(id: first.localIdentifier) }
    }

    private func requestImageData(for asset: PHAsset, completion: @escaping (Data?) -> Void) {
        let options = PHImageRequestOptions()
        options.isSynchronous = false
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true

        if #available(iOS 13, *) {
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, _ in completion(data) }
        } else {
            PHImageManager.default().requestImageData(for: asset, options: options) { data, _, _ in completion(data) }
        }
    }

    private func getLastProcessed() -> String? { return UserDefaults.standard.string(forKey: userDefaultsKey) }
    func setLastProcessed(id: String) { UserDefaults.standard.set(id, forKey: userDefaultsKey) }
    private func recordCurrentLatestAsset() {
        let options = PHFetchOptions(); options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]; options.fetchLimit = 1
        let assets = PHAsset.fetchAssets(with: .image, options: options)
        if let first = assets.firstObject { setLastProcessed(id: first.localIdentifier) }
    }

    // expose notification helper for UploadQueue
    func sendLocalNotification(title: String, body: String) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            if settings.authorizationStatus != .authorized {
                center.requestAuthorization(options: [.alert, .sound]) { granted, _ in if granted { self.postNotification(title: title, body: body) } }
            } else { self.postNotification(title: title, body: body) }
        }
    }
    private func postNotification(title: String, body: String) {
        let content = UNMutableNotificationContent(); content.title = title; content.body = body; content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }
}
