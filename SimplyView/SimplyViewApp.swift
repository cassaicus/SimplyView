import SwiftUI

// MARK: アプリの起動エントリポイント（macOSアプリの起動処理）
@main
struct SimplyViewApp: App {
    // アプリ全体で共有される画像表示モデル（画像一覧や拡大率などを管理）
    @StateObject private var model = ImageViewerModel()
    // NSPageController を強制再構築するための識別子（主にリサイズ・見開き用）
    @State private var viewerID = UUID()
    // AppDelegate を SwiftUI に統合（AppKit の連携に必要）
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    // 設定ダイアログ表示フラグ
    @State private var showSettings = false
    
    // コンストラクタ（アプリ初期化時に AppDelegate に model を渡す）
    init() {
        appDelegate.model = model
    }
    // アプリの UI（Scene）定義
    var body: some Scene {
        // メインウィンドウの定義（タイトルと識別子を指定）
        Window("画像ビューア", id: "mainWindow") {
            // SwiftUI のメインビューを表示
            ContentView(model: model, viewerID: $viewerID, showSettings: $showSettings)
            // ビューが表示されたときに AppDelegate 経由でファイル受け取り処理を登録
                .onAppear {
                    appDelegate.onOpenFilesWithSelected = { imageFiles, selected in
                        // 対象フォルダに画像が1枚もなければアラートを表示して処理中止
                        if imageFiles.isEmpty {
                            let alert = NSAlert()
                            alert.messageText = "画像が見つかりません"
                            alert.informativeText = "選択されたフォルダには対応する画像ファイルがありません。"
                            alert.alertStyle = .warning
                            alert.addButton(withTitle: "OK")
                            alert.runModal()
                            return
                        }
                        // 読み込んだ画像一覧をモデルに反映
                        model.images = imageFiles
                        // 拡大率・オフセットなどの状態を初期化
                        model.scale = 1.0
                        model.offset = .zero
                        // 選択された画像のインデックスを取得（見ていた画像が中心になる）
                        model.currentIndex = imageFiles.firstIndex(of: selected) ?? 0
                        // PageController を強制リフレッシュ（再描画）
                        viewerID = UUID()
                        // サムネイル画像をバックグラウンドスレッドで順次読み込み
                        DispatchQueue.global(qos: .userInitiated).async {
                            for url in imageFiles {
                                // すでにサムネイルがある場合はスキップ
                                if model.thumbnail(for: url) != nil { continue }
                                // NSImage を読み込んでリサイズ処理（40x40サムネイル）
                                if let image = NSImage(contentsOf: url) {
                                    let thumb = model.resizeImage(image: image, size: NSSize(width: 40, height: 40))
                                    // メインスレッドでキャッシュに登録（UI更新のため）
                                    DispatchQueue.main.async {
                                        model.setThumbnail(thumb, for: url)
                                    }
                                }
                                // CPU負荷軽減のために小さなウェイト（0.01秒）を入れる
                                Thread.sleep(forTimeInterval: 0.01)
                            }
                        }
                    }
                }
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("設定") {
                    showSettings = true
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}

