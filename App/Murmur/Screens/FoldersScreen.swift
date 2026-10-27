import SwiftUI
import SwiftData
import MurmurCore
import MurmurUI

/// All folders as a grid of cards. Matches design/iphone/Folders.dc.html.
struct FoldersScreen: View {
    let files: AudioFileStore
    /// Called with the card the person tapped. The screen then closes.
    let onSelect: (FolderCard) -> Void
    var startsWithNewFolder = false
    /// Pre-filled name for the New folder sheet (screenshots only).
    var sheetName = ""

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Folder.sortOrder) private var folders: [Folder]
    @Query private var notes: [Note]

    @State private var showNew = false
    @State private var renameTarget: Folder?
    @State private var renameText = ""
    @State private var deleteTarget: Folder?

    private var store: LibraryStore { LibraryStore(context: modelContext, files: files) }
    private var cards: [FolderCard] { FolderOverview.cards(folders: folders, notes: notes) }

    var body: some View {
        ZStack {
            MurmurTheme.Colors.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    topBar.padding(.top, 8).murmurEntrance(index: 0)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Folders")
                            .font(MurmurTheme.Fonts.largeTitle)
                            .foregroundStyle(MurmurTheme.Colors.textPrimary)
                            .accessibilityAddTraits(.isHeader)
                        Text(FolderOverview.subtitle(folderCount: cards.count, noteCount: notes.count))
                            .font(.subheadline)
                            .foregroundStyle(MurmurTheme.Colors.textSecondary)
                    }
                    .murmurEntrance(index: 1)

                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                        ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                            tile(card).murmurEntrance(index: index + 2)
                        }
                    }
                    if cards.isEmpty {
                        Text("No folders yet. Tap New folder to make one.")
                            .font(MurmurTheme.Fonts.body)
                            .foregroundStyle(MurmurTheme.Colors.textTertiary)
                            .padding(.top, 8)
                    }
                }
                .padding(.horizontal, MurmurTheme.Metrics.screenPadding)
                .padding(.bottom, 24)
            }
        }
        .preferredColorScheme(.dark)
        .toolbar(.hidden, for: .navigationBar)
        .task { if startsWithNewFolder { showNew = true } }
        .sheet(isPresented: $showNew) {
            NewFolderSheet(initialName: sheetName) { name, colorIndex in
                _ = store.createFolder(name: name, colorIndex: colorIndex)
                showNew = false
            }
            .presentationDetents([.height(420)])
            .presentationBackground(MurmurTheme.Colors.surface)
        }
        .alert("Rename folder", isPresented: Binding(get: { renameTarget != nil }, set: { if !$0 { renameTarget = nil } })) {
            TextField("Name", text: $renameText)
            Button("Save") {
                if let renameTarget { store.renameFolder(renameTarget, to: renameText) }
                renameTarget = nil
            }
            Button("Cancel", role: .cancel) { renameTarget = nil }
        }
        .confirmationDialog(
            "Delete this folder?",
            isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete folder", role: .destructive) {
                if let deleteTarget { store.deleteFolder(deleteTarget) }
                deleteTarget = nil
            }
            Button("Keep", role: .cancel) { deleteTarget = nil }
        } message: {
            Text("The notes inside stay in your library.")
        }
    }

    private var topBar: some View {
        HStack {
            HeaderCircleButton(symbol: "chevron.left", label: "Back to library") { dismiss() }
            Spacer()
            Button { showNew = true } label: {
                Label("New folder", systemImage: "plus")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(MurmurTheme.Colors.onAccent)
                    .padding(.horizontal, 14)
                    .frame(minHeight: MurmurTheme.Metrics.minTapTarget)
                    .background(Capsule().fill(MurmurTheme.Colors.accent))
            }
            .buttonStyle(MurmurPressStyle())
        }
    }

    private func tile(_ card: FolderCard) -> some View {
        Button {
            onSelect(card)
            dismiss()
        } label: {
            VStack(alignment: .leading, spacing: 20) {
                Image(systemName: "folder.fill")
                    .font(.headline)
                    .foregroundStyle(MurmurTheme.Colors.background)
                    .frame(width: 42, height: 42)
                    .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(MurmurTheme.Colors.folder(card.colorIndex)))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(card.name)
                        .font(MurmurTheme.Fonts.headline)
                        .foregroundStyle(MurmurTheme.Colors.textPrimary)
                        .lineLimit(1)
                    Text(card.meta)
                        .font(.footnote)
                        .foregroundStyle(MurmurTheme.Colors.textSecondary)
                        .lineLimit(1)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .murmurCard()
            .accessibilityElement(children: .combine)
        }
        .buttonStyle(MurmurPressStyle())
        .contextMenu {
            if case .folder(let id) = card.kind, let folder = folders.first(where: { $0.id == id }) {
                Button("Rename", systemImage: "pencil") {
                    renameText = folder.name
                    renameTarget = folder
                }
                Button("Delete", systemImage: "trash", role: .destructive) { deleteTarget = folder }
            }
        }
    }
}

/// The "New folder" sheet: a name and one of five colours.
struct NewFolderSheet: View {
    let onCreate: (String, Int) -> Void
    var initialName = ""
    @State private var name: String
    @State private var colorIndex = 3
    @FocusState private var focused: Bool

    private static let colorNames = ["Teal", "Lavender", "Orange", "Pink", "Sky"]

    init(initialName: String = "", onCreate: @escaping (String, Int) -> Void) {
        self.initialName = initialName
        self.onCreate = onCreate
        _name = State(initialValue: initialName)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New folder")
                .font(.title3.weight(.bold))
                .foregroundStyle(MurmurTheme.Colors.textPrimary)
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 8) {
                Text("Name").font(.footnote).foregroundStyle(MurmurTheme.Colors.textSecondary)
                TextField("Folder name", text: $name)
                    .focused($focused)
                    .font(MurmurTheme.Fonts.body)
                    .foregroundStyle(MurmurTheme.Colors.textPrimary)
                    .padding(.horizontal, 14)
                    .frame(height: 50)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(MurmurTheme.Colors.background))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(MurmurTheme.Colors.accent, lineWidth: MurmurTheme.Metrics.selectedBorderWidth))
                    .submitLabel(.done)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Color").font(.footnote).foregroundStyle(MurmurTheme.Colors.textSecondary)
                HStack(spacing: 12) {
                    ForEach(0..<Self.colorNames.count, id: \.self) { index in
                        Button { colorIndex = index } label: {
                            Circle()
                                .fill(MurmurTheme.Colors.folder(index))
                                .frame(width: 34, height: 34)
                                .padding(3)
                                .overlay(Circle().strokeBorder(colorIndex == index ? MurmurTheme.Colors.textPrimary : Color.clear, lineWidth: 3))
                                .frame(width: MurmurTheme.Metrics.minTapTarget, height: MurmurTheme.Metrics.minTapTarget)
                        }
                        .buttonStyle(MurmurPressStyle())
                        .accessibilityLabel(Self.colorNames[index])
                        .accessibilityAddTraits(colorIndex == index ? .isSelected : [])
                    }
                }
            }
            PrimaryButton("Create folder") {
                onCreate(name, colorIndex)
            }
            .opacity(name.trimmingCharacters(in: .whitespaces).isEmpty ? 0.45 : 1)
            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 12)
        .frame(maxHeight: .infinity, alignment: .top)
        .preferredColorScheme(.dark)
        .task { if initialName.isEmpty { focused = true } }
    }
}
