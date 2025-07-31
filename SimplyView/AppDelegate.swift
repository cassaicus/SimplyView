import SwiftUI                   // SwiftUI を使って UI を構築します
import AppKit                    // macOS 固有の AppKit 機能を使用します

// MARK: AppDelegate
class AppDelegate: NSObject, NSApplicationDelegate {
    // Finder から開かれた複数ファイルの処理用クロージャ（現在は未使用）
    var onOpenFile: (([URL]) -> Void)?
    // 選択されたファイルとそのフォルダ内の画像ファイル一覧を処理するクロージャ
    var onOpenFilesWithSelected: (([URL], URL) -> Void)?
    // モデルインスタンスを保持（サムネイル生成等で使用）
    var model: ImageViewerModel?
    
    // Finder などからアプリがファイルで開かれたときに呼び出される
    func application(_ application: NSApplication, open urls: [URL]) {
        // 最初のURLが存在しなければ処理終了
        guard let selectedFileURL = urls.first else { return }
        // 対象ファイルのあるフォルダのURLを取得
        let folderURL = selectedFileURL.deletingLastPathComponent()

        // フォルダ選択ダイアログのインスタンス生成
        let panel = NSOpenPanel()
        // ファイル選択を不可に
        panel.canChooseFiles = false
        // フォルダ選択を可能に
        panel.canChooseDirectories = true
        // 複数選択不可
        panel.allowsMultipleSelection = false
        // ダイアログのボタン名
        panel.prompt = "Select"
        // 初期ディレクトリを設定（現在のファイルのフォルダ）
        panel.directoryURL = folderURL
        
        // フォルダが選択された場合のみ処理を続ける
        if panel.runModal() == .OK, let confirmedFolder = panel.url {
            // 対応する画像拡張子の配列
            let allowedExtensions = ["jpg", "jpeg", "png", "gif", "bmp", "webp"]
            
            // フォルダ内のすべてのファイルを取得（隠しファイルは除外）
            if let files = try? FileManager.default.contentsOfDirectory(
                at: confirmedFolder,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) {
                // 対象となる画像ファイルだけをフィルタして並べ替える
                let imageFiles = files
                    .filter { allowedExtensions.contains($0.pathExtension.lowercased()) }
                //大文字小文字を区別
                //.sorted { $0.lastPathComponent < $1.lastPathComponent }
                //Finder風の自然順ソート
                    .sorted {
                        $0.lastPathComponent
                            .localizedStandardCompare($1.lastPathComponent)
                        == .orderedAscending
                    }
                // 一枚も画像がなければ終了
                guard !imageFiles.isEmpty else { return }
                
                // モデルに画像一覧と選択ファイルを通知
                onOpenFilesWithSelected?(imageFiles, selectedFileURL)
                
                // サムネイルを非同期で順次生成してキャッシュ
                DispatchQueue.global(qos: .userInitiated).async {
                    for url in imageFiles {
                        if ImageViewerModel.shared.thumbnail(for: url) != nil {
                            // 既にキャッシュされている場合はスキップ
                            continue
                        }
                        if let image = NSImage(contentsOf: url) {
                            // 40x40のサイズにリサイズしてサムネイルを作成
                            let thumb = ImageViewerModel.shared.resizeImage(image: image, size: NSSize(width: 40, height: 40))
                            DispatchQueue.main.async {
                                // メインスレッドでキャッシュに登録
                                ImageViewerModel.shared.setThumbnail(thumb, for: url)
                            }
                        }
                        // 高速処理によるCPU負荷を抑制するためのウェイト
                        Thread.sleep(forTimeInterval: 0.01)
                    }
                }
            }
        }
    }    //endfunc
    
    func openFolder(_ folderURL: URL) {
        
        // フォルダ選択ダイアログのインスタンス生成
        let panel = NSOpenPanel()

        panel.canChooseFiles = false // ファイル（単体）選択を無効にする（＝フォルダのみ選べる）
        panel.canChooseDirectories = true // フォルダの選択を有効にする
        panel.allowsMultipleSelection = false // フォルダの複数選択を禁止（1つだけ選択可）
        panel.prompt = "select" // ダイアログのボタン名（任意の文字列を設定可能）
        panel.directoryURL = folderURL // 最初に開くディレクトリの初期位置を設定

        // ユーザーが「選択」ボタンを押し、かつフォルダが選択された場合のみ処理を続行
        if panel.runModal() == .OK, let confirmedFolder = panel.url {

            // 対象とする画像の拡張子リスト（小文字限定）
            let imageExtensions = ["jpg", "jpeg", "png", "gif", "bmp", "webp"]

            // ファイル管理クラスのインスタンスを取得
            let fileManager = FileManager.default

            // 指定されたフォルダ内の全ファイルを取得（隠しファイルは除外）
            guard let files = try? fileManager.contentsOfDirectory(
                at: confirmedFolder,
                includingPropertiesForKeys: nil,
                options: .skipsHiddenFiles
            ) else { return } // ファイル取得に失敗した場合は処理中止

            // 拡張子が画像と一致するファイルだけを抽出し、ファイル名でソート
            let imageFiles = files.filter { url in
                imageExtensions.contains(url.pathExtension.lowercased())
            }.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })

            // フォルダに画像が1枚もなければアラート表示して処理を終了
            guard !imageFiles.isEmpty else {
                let alert = NSAlert()
                alert.messageText = "This Folder NO image"
                alert.runModal()
                return
            }

            // 最初の画像を選択状態として扱う
            let selected = imageFiles.first!

            // コールバック（クロージャ）を使って呼び出し元に画像一覧と選択画像を通知
            onOpenFilesWithSelected?(imageFiles, selected)
        }

    }
    
}

