import Foundation

class UploadQueue {
    static let shared = UploadQueue()

    struct QueueItem: Codable {
        let id: String
        let filename: String
        var attempts: Int
        let createdAt: Date
    }

    private let fileManager = FileManager.default
    private let uploadsDir: URL
    private let indexFile: URL
    private var items: [QueueItem] = []
    private let q = DispatchQueue(label: "UploadQueue.serial")
    private var working = false
    private let maxAttempts = 5

    private init() {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        uploadsDir = docs.appendingPathComponent("Uploads", isDirectory: true)
        indexFile = uploadsDir.appendingPathComponent("queue.json")
        try? fileManager.createDirectory(at: uploadsDir, withIntermediateDirectories: true, attributes: nil)
        loadIndex()
    }

    func enqueue(data: Data, id: String) {
        q.async {
            let uuid = UUID().uuidString
            let filename = "\(Date().timeIntervalSince1970)-\(uuid).dat"
            let fileURL = self.uploadsDir.appendingPathComponent(filename)
            do {
                try data.write(to: fileURL, options: .atomic)
                let item = QueueItem(id: id, filename: filename, attempts: 0, createdAt: Date())
                self.items.append(item)
                self.saveIndex()
                self.processNext()
            } catch {
                print("UploadQueue: failed to write file: \(error)")
            }
        }
    }

    private func loadIndex() {
        q.sync {
            do {
                if fileManager.fileExists(atPath: indexFile.path) {
                    let data = try Data(contentsOf: indexFile)
                    let decoder = JSONDecoder()
                    self.items = try decoder.decode([QueueItem].self, from: data)
                } else {
                    self.items = []
                }
            } catch {
                print("UploadQueue: failed to load index: \(error)")
                self.items = []
            }
            // 清理孤立文件与索引不一致项
            self.cleanupOrphanFiles()
        }
    }

    private func cleanupOrphanFiles() {
        do {
            let files = try fileManager.contentsOfDirectory(atPath: uploadsDir.path)
            var referenced = Set(self.items.map { $0.filename })
            for f in files where f != indexFile.lastPathComponent {
                if !referenced.contains(f) {
                    let p = uploadsDir.appendingPathComponent(f)
                    if p.pathExtension == "dat" {
                        try? fileManager.removeItem(at: p)
                    }
                }
            }
            var validItems: [QueueItem] = []
            for item in self.items {
                let p = uploadsDir.appendingPathComponent(item.filename)
                if fileManager.fileExists(atPath: p.path) {
                    validItems.append(item)
                }
            }
            if validItems.count != self.items.count {
                self.items = validItems
                saveIndex()
            }
        } catch {
            print("UploadQueue: cleanup failed: \(error)")
        }
    }

    private func saveIndex() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(self.items)
            try data.write(to: indexFile, options: .atomic)
        } catch {
            print("UploadQueue: failed to save index: \(error)")
        }
    }

    private func processNext() {
        guard !working else { return }
        guard items.count > 0 else { return }
        working = true
        let next = items.removeFirst()
        saveIndex()
        Task {
            let success = await self.uploadItem(next)
            q.async {
                if success {
                    let fileURL = self.uploadsDir.appendingPathComponent(next.filename)
                    try? self.fileManager.removeItem(at: fileURL)
                    PhotoMonitor.shared.setLastProcessed(id: next.id)
                } else {
                    var failed = next
                    failed.attempts += 1
                    if failed.attempts >= self.maxAttempts {
                        PhotoMonitor.shared.sendLocalNotification(title: "上传失败", body: "文件 \(failed.filename) 多次尝试失败，已放弃")
                        let fileURL = self.uploadsDir.appendingPathComponent(failed.filename)
                        try? self.fileManager.removeItem(at: fileURL)
                    } else {
                        self.items.append(failed)
                    }
                }
                self.saveIndex()
                self.working = false
                self.processNext()
            }
        }
    }

    private func uploadItem(_ item: QueueItem) async -> Bool {
        let fileURL = uploadsDir.appendingPathComponent(item.filename)
        guard let data = try? Data(contentsOf: fileURL) else { return false }

        var attempt = item.attempts
        while attempt < maxAttempts {
            do {
                let presign = try await NetworkManager.getPresignedURL(contentType: "image/jpeg", ext: "jpg")
                guard let url = URL(string: presign.url) else { return false }
                var req = URLRequest(url: url)
                req.httpMethod = "PUT"
                req.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
                let (_, resp) = try await URLSession.shared.upload(for: req, from: data)
                if let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                    PhotoMonitor.shared.sendLocalNotification(title: "上传成功", body: presign.key)
                    return true
                } else {
                    attempt += 1
                    let waitSec = UInt64(pow(2.0, Double(attempt)))
                    try await Task.sleep(nanoseconds: waitSec * 1_000_000_000)
                }
            } catch {
                attempt += 1
                let waitSec = UInt64(pow(2.0, Double(attempt)))
                do { try await Task.sleep(nanoseconds: waitSec * 1_000_000_000) } catch { }
            }
        }
        return false
    }
}
