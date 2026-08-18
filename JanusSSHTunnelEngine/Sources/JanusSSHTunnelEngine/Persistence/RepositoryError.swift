import Foundation

/// Repository 错误
enum RepositoryError: Error, LocalizedError, Equatable, Sendable {
    case fileNotFound(URL)
    case decodeFailed(String)
    case unsupportedVersion(found: Int, supported: Int)

    var errorDescription: String? {
        switch self {
        case .fileNotFound(let url):
            return "Profile file not found: \(url.lastPathComponent)"
        case .decodeFailed(let detail):
            return "Failed to decode profile file: \(detail)"
        case .unsupportedVersion(let found, let supported):
            return "Schema version \(found) is newer than supported (\(supported)). Please update Janus SSH."
        }
    }
}