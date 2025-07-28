import SwiftUI
import Combine

class BookmarkStore: ObservableObject {
    struct Bookmark: Identifiable, Codable, Equatable {
        var id = UUID()
        var title: String
        var url: URL
    }

    @Published var items: [Bookmark] = []
    @AppStorage("bookmarkedFolders") private var bookmarkedFoldersData: String = "[]"

    private weak var model: ImageViewerModel?

    init(model: ImageViewerModel) {
        self.model = model
        loadBookmarks()
    }

    var bookmarkedFolders: [String] {
        get {
            guard let data = bookmarkedFoldersData.data(using: .utf8) else { return [] }
            return (try? JSONDecoder().decode([String].self, from: data)) ?? []
        }
        set {
            bookmarkedFoldersData = (try? JSONEncoder().encode(newValue)).map { String(data: $0, encoding: .utf8)! } ?? "[]"
            loadBookmarks()
        }
    }

    func loadBookmarks() {
        items = bookmarkedFolders.compactMap { path in
            let url = URL(fileURLWithPath: path)
            return Bookmark(title: url.lastPathComponent, url: url)
        }
    }

    func addBookmark(from folderURL: URL) {
        let path = folderURL.path
        guard !bookmarkedFolders.contains(path) else { return }
        bookmarkedFolders.append(path)
    }

    func removeBookmark(for folderURL: URL) {
        let path = folderURL.path
        bookmarkedFolders.removeAll { $0 == path }
    }

    func removeAll() {
        bookmarkedFolders = []
    }

    func isBookmarked(_ folderURL: URL) -> Bool {
        return bookmarkedFolders.contains(folderURL.path)
    }
}

struct BookmarkCommands: Commands {
    @ObservedObject var store: BookmarkStore
    @ObservedObject var model: ImageViewerModel
    var appDelegate: AppDelegate
    var body: some Commands {
        CommandMenu("Bookmark") {
            
            ForEach(store.items) { bookmark in
                   Button(action: {
                       appDelegate.openFolder(bookmark.url)
                        //print(bookmark.url)
                   }) {
                       Text(bookmark.title)
                   }
               }
            Divider()
            // 現在の画像フォルダを追加
            Button(action: {
                guard model.images.indices.contains(model.currentIndex) else { return }
                let folderURL = model.images[model.currentIndex].deletingLastPathComponent()
                store.addBookmark(from: folderURL)
            }) {
                Text("addBookmark")
            }
            // 現在の画像フォルダを削除
            Button(action: {
                guard model.images.indices.contains(model.currentIndex) else { return }
                let folderURL = model.images[model.currentIndex].deletingLastPathComponent()
                store.removeBookmark(for: folderURL)
            }) {
                Text("removeBookmark")
            }

            Divider()

            Button(action: {
                store.removeAll()
            }) {
                Text("removeAll")
            }
        }
    }
}
