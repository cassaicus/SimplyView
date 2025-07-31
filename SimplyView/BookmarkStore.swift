import SwiftUI        // SwiftUIのUI要素やデータバインディングを使用
import Combine        // ObservableObjectなどリアクティブ機能を使用

// ブックマーク管理用のデータモデル（フォルダの登録・削除・保存を行う）
class BookmarkStore: ObservableObject {

    // 1つのブックマークデータ（ID、表示名、URL）を定義。Codableで保存可能に
    struct Bookmark: Identifiable, Codable, Equatable {
        var id = UUID()
        var title: String         // 表示用タイトル（例：フォルダ名）
        var url: URL              // 実際のフォルダのパス
    }

    // 表示用のブックマーク配列（UIと同期）
    @Published var items: [Bookmark] = []

    // AppStorageを使って永続的に保存（UserDefaultsと同様だがSwiftUIに最適化）
    @AppStorage("bookmarkedFolders") private var bookmarkedFoldersData: String = "[]"

    // 画像モデル（現在の画像などを取得するため）
    private weak var model: ImageViewerModel?

    // 初期化時にモデルを受け取り、保存済みブックマークを読み込む
    init(model: ImageViewerModel) {
        self.model = model
        loadBookmarks()
    }

    // AppStorageの文字列データを配列に変換して取得
    var bookmarkedFolders: [String] {
        get {
            guard let data = bookmarkedFoldersData.data(using: .utf8) else { return [] }
            return (try? JSONDecoder().decode([String].self, from: data)) ?? []
        }
        set {
            // 新しいブックマーク配列をJSON文字列に変換して保存
            bookmarkedFoldersData = (try? JSONEncoder().encode(newValue))
                .map { String(data: $0, encoding: .utf8)! } ?? "[]"
            //print(bookmarkedFoldersData)
            loadBookmarks() // 表示用のitemsも更新
        }
    }

    // 表示用のBookmark構造体配列を作成（title付き）
    func loadBookmarks() {
        items = bookmarkedFolders.compactMap { path in
            let url = URL(fileURLWithPath: path)
            return Bookmark(title: url.lastPathComponent, url: url)
        }
    }

    // ブックマークを追加（すでに登録されていれば無視）
    func addBookmark(from folderURL: URL) {
        let path = folderURL.path
        guard !bookmarkedFolders.contains(path) else { return }
        bookmarkedFolders.append(path)
    }

    // ブックマークを削除
    func removeBookmark(for folderURL: URL) {
        let path = folderURL.path
        bookmarkedFolders.removeAll { $0 == path }
    }

    // FolderSelect画像のないフォルダでも登録できる
    func FolderSelect() {
        // フォルダ選択ダイアログのインスタンス生成
        let panel = NSOpenPanel()
        // ファイル選択を不可に
        panel.canChooseFiles = false
        // フォルダ選択を可能に
        panel.canChooseDirectories = true
        // 複数選択不可
        panel.allowsMultipleSelection = false
        // ダイアログのボタン名
        panel.prompt = "select"
        
        // ユーザーが「選択」ボタンを押し、かつフォルダが選択された場合のみ処理を続行
        if panel.runModal() == .OK, let confirmedFolder = panel.url {
            // ブックマークを追加
            addBookmark(from: confirmedFolder)
        }
    }

    // すべてのブックマークを削除
    func removeAll() {
        bookmarkedFolders = []
    }
    
    //フォルダーを開く
    func folderopen(from folderURL: URL) {
        NSWorkspace.shared.open(folderURL)
    }
}


// SwiftUIのメニューコマンド拡張（CommandMenu）を定義
struct BookmarkCommands: Commands {
    // ブックマーク管理
    @ObservedObject var store: BookmarkStore
    // 現在の画像情報
    @ObservedObject var model: ImageViewerModel
    // フォルダを開くために必要な機能を持つ
    var appDelegate: AppDelegate

    var body: some Commands {
        // メニュータイトル「Bookmark」
        CommandMenu("Bookmark") {
            
            //AddBookmarkメニュー
            Button("AddBookmark") {
                guard model.images.indices.contains(model.currentIndex) else { return }
                let folderURL = model.images[model.currentIndex].deletingLastPathComponent()
                //ブックマークを追加
                store.addBookmark(from: folderURL)
            }
            // currentIndex が無効、または URL がフォルダにならない場合に無効化
            .disabled({
                guard model.images.indices.contains(model.currentIndex) else { return true }
                let folderURL = model.images[model.currentIndex].deletingLastPathComponent()
                return !FileManager.default.fileExists(atPath: folderURL.path, isDirectory: nil)
            }())

            // BookmarkFolder Select
            Button(action: {
                store.FolderSelect()
            }) {
                Text("BookmarkFolder Select")
            }
            
            // 現在の画像のフォルダをブックマークから削除
            Menu("RemoveBookmark") {
                if store.items.isEmpty {
                    Text("No bookmarks")
                } else {
                    ForEach(store.items) { bookmark in
                        Button(bookmark.title) {
                            store.removeBookmark(for: bookmark.url)
                        }
                    }
                    // 区切り線
                    Divider()
                    // ブックマークをすべて削除
                    Button(action: {
                        store.removeAll()
                    }) {
                        Text("RemoveAll")
                    }
                }
            }
            
            // 区切り線
            Divider()
            
            // ブックマークされた各フォルダをリスト表示
            ForEach(store.items) { bookmark in
                Button(action: {
                    // フォルダを画像ビューアで開く
                    appDelegate.openFolder(bookmark.url)
                }) {
                    // メニュー項目にフォルダ名を表示
                    Text(bookmark.title)
                }
            }
        }
    }
}
