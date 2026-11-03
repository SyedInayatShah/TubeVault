import SwiftUI

/// Sheet for deleting several videos (or Shorts) at once: small thumbnails to tick, Select All, Delete.
struct BulkDeleteView: View {
    let section: SidebarItem

    @Environment(LibraryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<String> = []
    @State private var confirming = false

    private var isShorts: Bool { section == .shorts }
    private var noun: String { isShorts ? "Short" : "Video" }
    private var videos: [Video] { store.videos(for: section) }
    private var allSelected: Bool { !videos.isEmpty && selected.count == videos.count }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Delete \(noun)s").font(.headline)
                    Text(selected.isEmpty ? "Click the \(noun.lowercased())s you want to delete."
                                          : "\(selected.count) of \(videos.count) selected")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(allSelected ? "Deselect All" : "Select All") {
                    selected = allSelected ? [] : Set(videos.map(\.id))
                }
                .keyboardShortcut("a")
                .disabled(videos.isEmpty)
            }
            .padding(16)

            Divider()

            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: isShorts ? 92 : 150), spacing: 12)], spacing: 14) {
                    ForEach(videos) { video in
                        tile(video)
                    }
                }
                .padding(16)
            }
            .overlay {
                if videos.isEmpty {
                    Text("No \(noun.lowercased())s to delete.").foregroundStyle(.secondary)
                }
            }

            Divider()

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(selected.isEmpty ? "Delete" : "Delete \(selected.count)", role: .destructive) {
                    confirming = true
                }
                .keyboardShortcut(.delete, modifiers: [])
                .tint(.red)
                .buttonStyle(.borderedProminent)
                .disabled(selected.isEmpty)
            }
            .padding(16)
        }
        .frame(width: 640, height: 520)
        .confirmationDialog(
            "Delete \(selected.count) \(noun.lowercased())\(selected.count == 1 ? "" : "s")?",
            isPresented: $confirming
        ) {
            Button("Delete", role: .destructive, action: deleteSelected)
        } message: {
            Text("The downloaded files are removed from your Mac. You can download them again from YouTube.")
        }
    }

    private func tile(_ video: Video) -> some View {
        let isOn = selected.contains(video.id)
        return VStack(alignment: .leading, spacing: 5) {
            Color.clear
                .aspectRatio(isShorts ? 9.0 / 16 : 16.0 / 9, contentMode: .fit)
                .overlay { ThumbnailImage(url: store.thumbnailURL(for: video)) }
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(isOn ? Color.accentColor : .clear, lineWidth: 3)
                }
                .overlay(alignment: .topTrailing) {
                    Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 18, weight: .semibold))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, isOn ? Color.accentColor : .black.opacity(0.35))
                        .shadow(radius: 2)
                        .padding(6)
                }
                .opacity(isOn ? 0.85 : 1)
            Text(video.title)
                .font(.caption)
                .lineLimit(2)
                .foregroundStyle(isOn ? .primary : .secondary)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if isOn { selected.remove(video.id) } else { selected.insert(video.id) }
        }
    }

    private func deleteSelected() {
        for video in videos where selected.contains(video.id) {
            store.delete(video)
        }
        selected = []
        dismiss()
    }
}
