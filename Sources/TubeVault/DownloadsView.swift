import SwiftUI

struct DownloadsView: View {
    @Environment(DownloadManager.self) private var downloads
    @Environment(UIState.self) private var ui

    var body: some View {
        Group {
            if downloads.tasks.isEmpty {
                ContentUnavailableView {
                    Label("Nothing Downloading", systemImage: "arrow.down.circle")
                } description: {
                    Text("Downloads in progress show up here. Finished videos move to your library and play offline.")
                } actions: {
                    Button("Download from Link…") { ui.showingAddLink = true }
                }
            } else {
                List {
                    ForEach(downloads.tasks) { task in
                        DownloadRow(task: task)
                            .padding(.vertical, 6)
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle("Downloading")
        .navigationSubtitle(downloads.tasks.isEmpty ? "" : "\(downloads.activeTasks.count) in progress")
    }
}

struct DownloadRow: View {
    @Environment(DownloadManager.self) private var downloads
    let task: DownloadTask

    var body: some View {
        HStack(spacing: 14) {
            AsyncImage(url: task.thumbnail) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                ZStack {
                    Rectangle().fill(.quaternary)
                    ProgressView().controlSize(.small)
                }
            }
            .frame(width: 128, height: 72)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                Text(task.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                if !task.channel.isEmpty {
                    Text(task.channel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                switch task.state {
                case .failed(let message):
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                        .textSelection(.enabled)
                case .starting:
                    ProgressView().progressViewStyle(.linear)
                    Text("Getting video info…").font(.caption).foregroundStyle(.secondary)
                case .downloading, .finishing:
                    ProgressView(value: task.progress)
                        .progressViewStyle(.linear)
                        .tint(.red)
                    Text(statusLine)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            if task.isFailed {
                Button("Retry") { downloads.retry(task) }
                Button {
                    downloads.remove(task)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Remove")
            } else {
                Button {
                    downloads.cancel(task)
                } label: {
                    Image(systemName: "xmark.circle.fill").font(.title3)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Cancel download")
            }
        }
    }

    private var statusLine: String {
        if task.state == .finishing { return "Finishing up…" }
        var parts = ["\(Int(task.progress * 100))%"]
        if let speed = task.speed, speed > 0 {
            parts.append(Format.bytes(Int64(speed)) + "/s")
        }
        if let eta = task.eta, eta > 0 {
            parts.append(Format.time(eta) + " left")
        }
        return parts.joined(separator: " · ")
    }
}
