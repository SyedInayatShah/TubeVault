import SwiftUI

struct SidebarView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(DownloadManager.self) private var downloads
    @Environment(UIState.self) private var ui

    @Binding var selection: SidebarItem?

    @State private var newName = ""
    @State private var renaming: VideoLibrary?
    @State private var renameText = ""
    @State private var deleting: VideoLibrary?

    var body: some View {
        @Bindable var ui = ui

        List(selection: $selection) {
            Section("Videos") {
                Label("All Videos", systemImage: "play.rectangle.on.rectangle")
                    .badge(store.videos(for: .all).count)
                    .tag(SidebarItem.all)
                    .contextMenu {
                        Button("Delete Videos…") { ui.bulkDelete = .all }
                            .disabled(store.videos(for: .all).isEmpty)
                    }

                Label("Shorts", systemImage: "film.stack")
                    .badge(store.videos(for: .shorts).count)
                    .tag(SidebarItem.shorts)
                    .contextMenu {
                        Button("Delete Shorts…") { ui.bulkDelete = .shorts }
                            .disabled(store.videos(for: .shorts).isEmpty)
                    }

                Label("Unsorted", systemImage: "tray")
                    .badge(store.videos(for: .unsorted).count)
                    .tag(SidebarItem.unsorted)
                    .dropDestination(for: String.self) { ids, _ in
                        ids.forEach { store.move(videoID: $0, to: nil) }
                        return true
                    }

                downloadingRow
                    .tag(SidebarItem.downloads)
            }

            Section("Libraries") {
                ForEach(store.libraries) { library in
                    Label(library.name, systemImage: "folder")
                        .badge(store.count(in: library.id))
                        .tag(SidebarItem.library(library.id))
                        .dropDestination(for: String.self) { ids, _ in
                            ids.forEach { store.move(videoID: $0, to: library.id) }
                            return true
                        }
                        .contextMenu {
                            Button("Rename…") {
                                renameText = library.name
                                renaming = library
                            }
                            Divider()
                            Button("Delete Library", role: .destructive) { deleting = library }
                        }
                }
                if store.libraries.isEmpty {
                    Text("Create a library to organise your videos.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .selectionDisabled()
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button {
                    ui.showingNewLibrary = true
                } label: {
                    Label("New Library", systemImage: "plus.circle")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                Button {
                    ui.showingSetup = true
                } label: {
                    Image(systemName: "questionmark.circle")
                }
                .help("Setup Guide")
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .sheet(isPresented: Binding(
            get: { ui.bulkDelete != nil },
            set: { if !$0 { ui.bulkDelete = nil } }
        )) {
            if let section = ui.bulkDelete { BulkDeleteView(section: section) }
        }
        .alert("New Library", isPresented: $ui.showingNewLibrary) {
            TextField("Name", text: $newName)
            Button("Create") {
                let name = newName.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty {
                    selection = .library(store.createLibrary(named: name).id)
                }
                newName = ""
            }
            Button("Cancel", role: .cancel) { newName = "" }
        }
        .alert("Rename Library", isPresented: Binding(
            get: { renaming != nil },
            set: { if !$0 { renaming = nil } }
        )) {
            TextField("Name", text: $renameText)
            Button("Rename") {
                if let renaming, !renameText.trimmingCharacters(in: .whitespaces).isEmpty {
                    store.rename(renaming.id, to: renameText)
                }
                renaming = nil
            }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
        .confirmationDialog(
            "Delete “\(deleting?.name ?? "")”?",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })
        ) {
            Button("Delete Library", role: .destructive) {
                if let deleting {
                    if selection == .library(deleting.id) { selection = .all }
                    store.deleteLibrary(deleting.id)
                }
                deleting = nil
            }
        } message: {
            Text("The videos inside won’t be deleted — they’ll move to Unsorted.")
        }
    }

    private var downloadingRow: some View {
        HStack {
            Label("Downloading", systemImage: "arrow.down.circle")
            Spacer()
            if let progress = downloads.overallProgress {
                ProgressView(value: progress)
                    .progressViewStyle(.circular)
                    .controlSize(.mini)
                Text("\(downloads.activeTasks.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            } else if !downloads.tasks.isEmpty {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.orange)
            }
        }
    }
}
