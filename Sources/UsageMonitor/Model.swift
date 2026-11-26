import Foundation
import UsageKit

struct UsageError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}

// MARK: - Helpers shared by providers

typealias JSON = [String: Any]

func num(_ value: Any?) -> Double? {
    if let n = value as? NSNumber { return n.doubleValue }
    if let s = value as? String { return Double(s) }
    return nil
}

func parseJSON(_ data: Data) -> JSON? {
    try? JSONSerialization.jsonObject(with: data) as? JSON
}

func homeFile(_ path: String) -> URL {
    FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(path)
}

extension Date {
    /// Parses ISO-8601 with any number of fractional digits (APIs return 0–6).
    static func iso(_ value: Any?) -> Date? {
        guard var s = value as? String else { return nil }
        if let r = s.range(of: #"\.\d+"#, options: .regularExpression) { s.removeSubrange(r) }
        return ISO8601DateFormatter().date(from: s)
    }
}

enum Keychain {
    /// Reads via /usr/bin/security, which the CLIs used to create these items,
    /// so macOS doesn't prompt for access on every rebuild of this app.
    static func password(service: String) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        p.arguments = ["find-generic-password", "-s", service, "-w"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { return nil }
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum HTTP {
    static func json(_ request: URLRequest) async throws -> JSON {
        var request = request
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch status {
        case 200..<300: break
        case 401: throw UsageError("Sign-in expired — open the CLI once to refresh it")
        case 429: throw UsageError("Rate limited — will retry shortly")
        default: throw UsageError("Request failed (HTTP \(status))")
        }
        guard let json = parseJSON(data) else { throw UsageError("Unexpected response") }
        return json
    }
}
