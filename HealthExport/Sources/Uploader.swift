import Foundation
import Security

enum Uploader {
    struct UploadError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// POSTs the CSV as the raw request body (Content-Type: text/csv).
    static func upload(csv: Data, filename: String, range: String, dataset: String, to url: URL, token: String) async throws {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("text/csv", forHTTPHeaderField: "Content-Type")
        request.setValue(filename, forHTTPHeaderField: "X-Filename")
        request.setValue(range, forHTTPHeaderField: "X-Date-Range")
        request.setValue(dataset, forHTTPHeaderField: "X-Dataset")   // "daily" or "samples"
        if !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (_, response) = try await URLSession.shared.upload(for: request, from: csv)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw UploadError(message: "Dashboard responded with HTTP \(code)")
        }
    }
}

enum Keychain {
    static func set(_ value: String, for key: String) {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                   kSecAttrAccount as String: key]
        SecItemDelete(base as CFDictionary)
        guard !value.isEmpty else { return }
        var add = base
        add[kSecValueData as String] = Data(value.utf8)
        // Readable after first unlock so background runs can use it.
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    static func get(_ key: String) -> String {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrAccount as String: key,
                                    kSecReturnData as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
        var out: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return "" }
        return String(decoding: data, as: UTF8.self)
    }
}
