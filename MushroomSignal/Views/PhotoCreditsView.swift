// MushroomSignal/Views/PhotoCreditsView.swift
import SwiftUI
import MushroomSignalCore

struct PhotoCreditsView: View {
    let photos: [SpeciesPhoto]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(photos) { photo in
                VStack(alignment: .leading, spacing: DesignSystem.spacingTight) {
                    Text(photo.photographer).font(.system(size: DesignSystem.bodySize, weight: .bold))
                    Text(photo.license).font(.system(size: DesignSystem.captionSize)).foregroundStyle(.secondary)
                    Link(destination: photo.sourceURL) {
                        Text(photo.sourceURL.absoluteString)
                            .font(.system(size: DesignSystem.captionSize))
                            .lineLimit(1)
                    }
                }
            }
            .navigationTitle("Zdroje fotografií")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Zavrieť") { dismiss() }
                }
            }
        }
    }
}
