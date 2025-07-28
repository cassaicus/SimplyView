import SwiftUI                   // SwiftUI を使って UI を構築します
import AppKit                    // macOS 固有の AppKit 機能を使用します

// MARK: AppDelegate
class AppDelegate: NSObject, NSApplicationDelegate {
    // Finder から開かれた複数ファイルの処理用クロージャ（現在は未使用）
    var onOpenFile: (([URL]) -> Void)?
    // 選択されたファイルとそのフォルダ内の画像ファイル一覧を処理するクロージャ
    var onOpenFilesWithSelected: (([URL], URL) -> Void)?
    // ← モデルインスタンスを保持（サムネイル生成等で使用）
    var model: ImageViewerModel?
    
    // Finder などからアプリがファイルで開かれたときに呼び出される
    func application(_ application: NSApplication, open urls: [URL]) {
        // 最初のURLが存在しなければ処理終了
        guard let selectedFileURL = urls.first else { return }
        // 対象ファイルのあるフォルダのURLを取得
        let folderURL = selectedFileURL.deletingLastPathComponent()

        // フォルダ選択ダイアログのインスタンス生成
        let panel = NSOpenPanel()
        panel.canChooseFiles = false // ファイル選択を不可に
        panel.canChooseDirectories = true // フォルダ選択を可能に
        panel.allowsMultipleSelection = false // 複数選択不可
        panel.prompt = "このフォルダを開く" // ダイアログのボタン名
        panel.directoryURL = folderURL // 初期ディレクトリを設定（現在のファイルのフォルダ）
        
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
        panel.canChooseFiles = false // ファイル選択を不可に
        panel.canChooseDirectories = true // フォルダ選択を可能に
        panel.allowsMultipleSelection = false // 複数選択不可
        panel.prompt = "このフォルダを開く" // ダイアログのボタン名
        panel.directoryURL = folderURL // 初期ディレクトリを設定（現在のファイルのフォルダ）
        
        if panel.runModal() == .OK, let confirmedFolder = panel.url {
            
            let imageExtensions = ["jpg", "jpeg", "png", "gif", "bmp", "webp"]
            let fileManager = FileManager.default
            guard let files = try? fileManager.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) else { return }
            
            let imageFiles = files.filter { url in
                imageExtensions.contains(url.pathExtension.lowercased())
            }.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
            
            guard !imageFiles.isEmpty else {
                let alert = NSAlert()
                alert.messageText = "このフォルダには画像がありません"
                alert.runModal()
                return
            }
            
            let selected = imageFiles.first!
            onOpenFilesWithSelected?(imageFiles, selected)
        }
    }
    
}

