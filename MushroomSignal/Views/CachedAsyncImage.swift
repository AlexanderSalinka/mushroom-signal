// MushroomSignal/Views/CachedAsyncImage.swift
import SwiftUI
import MushroomSignalCore

/// Like `AsyncImage`, but backed by `PhotoCache` — a photo already seen once loads
/// instantly from disk on every later appearance, including across app launches.
struct CachedAsyncImage<Content: View, PlaceholderContent: View>: View {
    let url: URL?
    @ViewBuilder let content: (Image) -> Content
    @ViewBuilder let placeholder: () -> PlaceholderContent

    @State private var loadedImage: Image?
    private static var sharedCache: PhotoCache { PhotoCache() }

    var body: some View {
        Group {
            if let loadedImage {
                content(loadedImage)
            } else {
                placeholder()
            }
        }
        .task(id: url) {
            guard let url else { return }
            do {
                let data = try await Self.sharedCache.cachedImageData(for: url)
                #if canImport(AppKit)
                if let nsImage = NSImage(data: data) {
                    loadedImage = Image(nsImage: nsImage)
                }
                #endif
            } catch {
                loadedImage = nil
            }
        }
    }
}
