import SwiftUI
// MARK: ── アプリ起動エントリ
@main
struct SimplyViewApp: App {
    @StateObject private var model = ImageViewerModel()
    @State private var viewerID = UUID()

    // ✅ モデルを AppDelegate に渡す
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        appDelegate.model = model
    }

    var body: some Scene {
        Window("画像ビューア", id: "mainWindow") {
            ContentView(model: model, viewerID: $viewerID)
                .onAppear {
                    appDelegate.onOpenFilesWithSelected = { imageFiles, selected in
                       
                        if imageFiles.isEmpty {
                            // ✅ 画像なしをユーザーに通知（NSAlert）
                            let alert = NSAlert()
                            alert.messageText = "画像が見つかりません"
                            alert.informativeText = "選択されたフォルダには対応する画像ファイルがありません。"
                            alert.alertStyle = .warning
                            alert.addButton(withTitle: "OK")
                            alert.runModal()
                            return
                        }

                        model.images = imageFiles
                        model.scale = 1.0
                        model.offset = .zero
                        model.currentIndex = imageFiles.firstIndex(of: selected) ?? 0
                        viewerID = UUID()

                        // ✅ 非同期でサムネイルを段階的に追加
                        DispatchQueue.global(qos: .userInitiated).async {
                            for url in imageFiles {
                                if model.thumbnail(for: url) != nil { continue }
                                if let image = NSImage(contentsOf: url) {
                                    let thumb = model.resizeImage(image: image, size: NSSize(width: 40, height: 40))
                                    DispatchQueue.main.async {
                                        model.setThumbnail(thumb, for: url)
                                    }
                                }
                                Thread.sleep(forTimeInterval: 0.01)
                            }
                        }
                    }
                }
        }
    }
}
