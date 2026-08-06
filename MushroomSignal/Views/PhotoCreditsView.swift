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
                    Text(photo.photographer).font(.subheadline.bold())
                    Text(photo.license).font(.caption).foregroundStyle(.secondary)
                    Link(destination: photo.sourceURL) {
                        Text(photo.sourceURL.absoluteString)
                            .font(.caption2)
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
