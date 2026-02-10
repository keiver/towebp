import Foundation

enum FileStatus: Equatable {
    case queued
    case converting
    case done
    case skipped
    case failed
}

struct FileItem: Identifiable {
    let id = UUID()
    let url: URL
    let fileName: String
    let originalSize: Int64?
    var status: FileStatus = .queued
    var resultSize: Int64?
    var errorMessage: String?

    var savings: Double? {
        guard let orig = originalSize, orig > 0, let result = resultSize else { return nil }
        return Double(orig - result) / Double(orig)
    }

    init(url: URL) {
        self.url = url
        self.fileName = url.lastPathComponent
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        self.originalSize = attrs?[.size] as? Int64
    }
}
