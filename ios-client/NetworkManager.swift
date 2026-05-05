import Foundation

struct PresignResponse: Codable {
    let url: String
    let key: String
}

enum NetworkError: Error {
    case invalidURL
    case serverError(String)
}

struct NetworkManager {
    // 修改为你的 presign server 地址（建议使用 https）
    // 本地测试时请使用 http://localhost:3000
    static var PRESIGN_SERVER = "http://localhost:3000"

    static func getPresignedURL(contentType: String, ext: String) async throws -> PresignResponse {
        guard let url = URL(string: PRESIGN_SERVER + "/get-presigned-url") else { throw NetworkError.invalidURL }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = ["contentType": contentType, "ext": ext]
        req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw NetworkError.serverError("no response") }
        guard (200...299).contains(http.statusCode) else {
            let txt = String(data: data, encoding: .utf8) ?? ""
            throw NetworkError.serverError("HTTP \(http.statusCode): \(txt)")
        }

        let decoder = JSONDecoder()
        return try decoder.decode(PresignResponse.self, from: data)
    }

    static func uploadData(to presignUrl: String, data: Data, contentType: String) async throws -> (Int, Data?) {
        guard let url = URL(string: presignUrl) else { throw NetworkError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = "PUT"
        req.setValue(contentType, forHTTPHeaderField: "Content-Type")
        req.httpBody = data

        let (respData, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw NetworkError.serverError("no response") }
        return (http.statusCode, respData)
    }
}
