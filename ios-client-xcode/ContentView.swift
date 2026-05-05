import SwiftUI

// 复制自 ios-client/ContentView.swift

struct ContentView: View {
    @State private var showingCamera = false
    @State private var imageData: Data? = nil
    @State private var statusText: String = "等待拍照"

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                if let data = imageData, let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 300)
                } else {
                    Rectangle().fill(Color.gray.opacity(0.2)).frame(height: 300)
                }

                Text(statusText)
                    .multilineTextAlignment(.center)
                    .padding()

                Button(action: {
                    showingCamera = true
                }) {
                    Text("拍照并上传")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
                .padding(.horizontal)

                Spacer()
            }
            .navigationTitle("R2 相机上传")
            .sheet(isPresented: $showingCamera) {
                ImagePicker(sourceType: .camera) { result in
                    showingCamera = false
                    switch result {
                    case .success(let data):
                        imageData = data
                        Task { await autoUpload(data: data) }
                    case .failure(let err):
                        statusText = "拍照失败：\(err.localizedDescription)"
                    }
                }
            }
        }
    }

    func autoUpload(data: Data) async {
        statusText = "请求 presigned URL..."
        let contentType = "image/jpeg"
        do {
            let presign = try await NetworkManager.getPresignedURL(contentType: contentType, ext: "jpg")
            statusText = "上传到 R2：\(presign.key)"
            let (code, body) = try await NetworkManager.uploadData(to: presign.url, data: data, contentType: contentType)
            if (200...299).contains(code) {
                statusText = "上传成功：\(presign.key)"
            } else {
                statusText = "上传失败，HTTP \(code)：\(String(data: body ?? Data(), encoding: .utf8) ?? "")"
            }
        } catch {
            statusText = "错误：\(error.localizedDescription)"
        }
    }
}
