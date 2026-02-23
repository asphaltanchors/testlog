#if os(macOS)
import Foundation
import UniformTypeIdentifiers

@discardableResult
func handleDroppedFileProviders(
    _ providers: [NSItemProvider],
    onURLs: @escaping ([URL]) -> Void
) -> Bool {
    let fileProviders = providers.filter {
        $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
    }
    guard !fileProviders.isEmpty else { return false }

    Task {
        let urls = await loadFileURLs(from: fileProviders)
        guard !urls.isEmpty else { return }
        await MainActor.run {
            onURLs(urls)
        }
    }

    return true
}

private func loadFileURLs(from providers: [NSItemProvider]) async -> [URL] {
    await withTaskGroup(of: URL?.self, returning: [URL].self) { group in
        for provider in providers {
            group.addTask {
                await loadFileURL(from: provider)
            }
        }

        var urls: [URL] = []
        for await maybeURL in group {
            guard let url = maybeURL else { continue }
            urls.append(url)
        }
        return urls
    }
}

private func loadFileURL(from provider: NSItemProvider) async -> URL? {
    await withCheckedContinuation { continuation in
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            if let url = item as? URL {
                continuation.resume(returning: url)
                return
            }

            if let data = item as? Data,
               let url = NSURL(absoluteURLWithDataRepresentation: data, relativeTo: nil) as URL? {
                continuation.resume(returning: url)
                return
            }

            if let string = item as? String,
               let url = URL(string: string) {
                continuation.resume(returning: url)
                return
            }

            continuation.resume(returning: nil)
        }
    }
}
#endif
