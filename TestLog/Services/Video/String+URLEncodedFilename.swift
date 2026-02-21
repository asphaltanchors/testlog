import Foundation

extension String {
    nonisolated var urlEncodedFilename: String {
        replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: " ", with: "-")
    }
}
