import SwiftUI                   // SwiftUI を使って UI を構築します
import AppKit                    // macOS 固有の AppKit 機能を使用します

// MARK: ── AppDelegate
class AppDelegate: NSObject, NSApplicationDelegate {
    var onOpenFile: (([URL]) -> Void)?  // Finder から開かれた複数ファイルの処理用クロージャ（現在は未使用）
    var onOpenFilesWithSelected: (([URL], URL) -> Void)?  // 選択されたファイルとそのフォルダ内の画像ファイル一覧を処理するクロージャ
    var model: ImageViewerModel? // ← モデルインスタンスを保持（サムネイル生成等で使用）
    
    // Finder などからアプリがファイルで開かれたときに呼び出される
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let selectedFileURL = urls.first else { return } // 最初のURLが存在しなければ処理終了
        let folderURL = selectedFileURL.deletingLastPathComponent() // 対象ファイルのあるフォルダのURLを取得
        
        let panel = NSOpenPanel() // フォルダ選択ダイアログのインスタンス生成
        panel.canChooseFiles = false // ファイル選択を不可に
        panel.canChooseDirectories = true // フォルダ選択を可能に
        panel.allowsMultipleSelection = false // 複数選択不可
        panel.prompt = "このフォルダを開く" // ダイアログのボタン名
        panel.directoryURL = folderURL // 初期ディレクトリを設定（現在のファイルのフォルダ）
        
        // フォルダが選択された場合のみ処理を続ける
        if panel.runModal() == .OK, let confirmedFolder = panel.url {
            let allowedExtensions = ["jpg", "jpeg", "png", "gif", "bmp", "tiff"] // 対応する画像拡張子の配列
            
            // フォルダ内のすべてのファイルを取得（隠しファイルは除外）
            if let files = try? FileManager.default.contentsOfDirectory(
                at: confirmedFolder,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) {
                // 対象となる画像ファイルだけをフィルタして並べ替える
                let imageFiles = files
                    .filter { allowedExtensions.contains($0.pathExtension.lowercased()) }
//.sorted { $0.lastPathComponent < $1.lastPathComponent } //大文字小文字を区別
                    .sorted {
                        $0.lastPathComponent
                            .localizedStandardCompare($1.lastPathComponent)
                        == .orderedAscending
                    } //Finder風の自然順ソート
                
                guard !imageFiles.isEmpty else { return } // 一枚も画像がなければ終了
                
                // モデルに画像一覧と選択ファイルを通知
                onOpenFilesWithSelected?(imageFiles, selectedFileURL)
                
                // サムネイルを非同期で順次生成してキャッシュ
                DispatchQueue.global(qos: .userInitiated).async {
                    for url in imageFiles {
                        if ImageViewerModel.shared.thumbnail(for: url) != nil {
                            continue // 既にキャッシュされている場合はスキップ
                        }
                        if let image = NSImage(contentsOf: url) {
                            // 40x40のサイズにリサイズしてサムネイルを作成
                            let thumb = ImageViewerModel.shared.resizeImage(image: image, size: NSSize(width: 40, height: 40))
                            DispatchQueue.main.async {
                                // メインスレッドでキャッシュに登録
                                ImageViewerModel.shared.setThumbnail(thumb, for: url)
                            }
                        }
                        Thread.sleep(forTimeInterval: 0.01) // 高速処理によるCPU負荷を抑制するためのウェイト
                    }
                }
            }
        }
    }
}


// MARK: ImageViewerModel
class ImageViewerModel: ObservableObject {
    static let shared = ImageViewerModel() // シングルトンインスタンス（外部から共有的にアクセス）
    

    //////////////
    // ← 既存のプロパティ群の中にこの2つを追加
    enum SpreadViewMode: Int {
        case none = 0
        case previousLeft
        case nextRight
    }

    @Published var spreadViewMode: SpreadViewMode = .none
    
    
    
    @Published var temporaryImageOverrides: [URL: NSImage] = [:]

    func overrideImage(for url: URL, with image: NSImage) {
        temporaryImageOverrides[url] = image
        objectWillChange.send() // 強制UI更新
    }

    func clearOverrides() {
        temporaryImageOverrides.removeAll()
    }
    
    
    
    //////////////
    
    

    
    @Published var images: [URL] = []       // 読み込まれた画像ファイルのURL配列（Viewがリアルタイムに監視）
    @Published var currentIndex = 0         // 現在表示中の画像インデックス
    @Published var scale: CGFloat = 1.0     // 現在の拡大率（ピンチ/ダブルクリックで変更）
    @Published var offset: CGSize = .zero   // 画像のオフセット（パン操作で使用）
    @Published var isLoading = false        // 読み込み中かどうか（インジケータ制御などで利用）
    
    private var _thumbnailCache: [URL: NSImage] = [:]  // URLとNSImageを結びつけるサムネイルキャッシュ
    
    var thumbnailCache: [URL: NSImage] {
        _thumbnailCache // 外部からは読み取り専用でアクセス
    }
    
    func setThumbnail(_ image: NSImage, for url: URL) {
        _thumbnailCache[url] = image // キャッシュに登録
        DispatchQueue.main.async {
            self.objectWillChange.send() // SwiftUI に手動で変更通知（UI更新トリガー）
        }
    }
    
    func thumbnail(for url: URL) -> NSImage? {
        return _thumbnailCache[url] // キャッシュから該当URLのサムネイルを返す
    }
    
    
    // フォルダから画像を読みだす
    func loadImagesFromDirectory(_ folder: URL) {
        let allowed = ["jpg","jpeg","png","gif","bmp","tiff"] // 対応画像拡張子
        
        DispatchQueue.global(qos: .userInitiated).async {
            if let urls = try? FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
            ) {
                let filtered = urls
                    .filter { allowed.contains($0.pathExtension.lowercased()) }
//.sorted { $0.lastPathComponent < $1.lastPathComponent } //大文字小文字を区別
                    .sorted {
                        $0.lastPathComponent
                            .localizedStandardCompare($1.lastPathComponent)
                        == .orderedAscending
                    } //Finder風の自然順ソート
                
                // メインスレッドでUI更新を行うためにディスパッチ
                DispatchQueue.main.async {
                    self.images = filtered          // フィルタ済画像リストをViewに反映
                    self.currentIndex = 0           // 表示位置を先頭に
                    self.scale = 1.0                // 拡大リセット
                    self.offset = .zero             // オフセットリセット
                    self._thumbnailCache.removeAll() // サムネイルキャッシュをクリア
                    self.isLoading = true           // 読み込み中に切り替え
                    
                    // 画像がない時は停止
                    if filtered.isEmpty {
                        self.isLoading = false
                        return
                    }
                }
                
                for url in filtered {
                    if let image = NSImage(contentsOf: url) {
                        let thumb = self.resizeImage(image: image, size: NSSize(width: 40, height: 40))
                        DispatchQueue.main.async {
                            self.setThumbnail(thumb, for: url) // サムネイルを設定
                        }
                    }
                    Thread.sleep(forTimeInterval: 0.01) // 負荷軽減のために少し待つ
                }
                
                DispatchQueue.main.async {
                    self.isLoading = false // 読み込み終了
                }
            }
        }
    }
    // リサイズ
    func resizeImage(image: NSImage, size: NSSize) -> NSImage {
        guard let rep = image.bestRepresentation(for: NSRect(origin: .zero, size: size), context: nil, hints: nil) else {
            return image // リサイズできない場合は元画像を返す
        }
        let resizedImage = NSImage(size: size)
        resizedImage.lockFocus() // 描画開始
        rep.draw(in: NSRect(origin: .zero, size: size)) // 指定サイズに描画
        resizedImage.unlockFocus() // 描画終了
        return resizedImage
    }
    // 見開き時のページ１
    func makeSpreadImage(current: URL, next: URL?) -> NSImage? {
        guard let img1 = NSImage(contentsOf: current),
              let img2 = next.flatMap({ NSImage(contentsOf: $0) }) else {
            return nil
        }
        
        let totalWidth = img1.size.width + img2.size.width
        let maxHeight = max(img1.size.height, img2.size.height)
        let size = NSSize(width: totalWidth, height: maxHeight)
        
        let newImage = NSImage(size: size)
        newImage.lockFocus()
        img1.draw(at: NSPoint(x: 0, y: 0), from: .zero, operation: .sourceOver, fraction: 1.0)
        img2.draw(at: NSPoint(x: img1.size.width, y: 0), from: .zero, operation: .sourceOver, fraction: 1.0)
        newImage.unlockFocus()
        
        return newImage
    }
    // 見開き時のページ2
//    func makeSpreadImagesec(current: URL, next: URL?) -> NSImage? {
//        guard let img1 = NSImage(contentsOf: current),
//              let img2 = next.flatMap({ NSImage(contentsOf: $0) }) else {
//            return nil
//        }
//        
//        let totalWidth = img1.size.width + img2.size.width
//        let maxHeight = max(img1.size.height, img2.size.height)
//        let size = NSSize(width: totalWidth, height: maxHeight)
//        
//        let newImage = NSImage(size: size)
//        newImage.lockFocus()
//        img2.draw(at: NSPoint(x: 0, y: 0), from: .zero, operation: .sourceOver, fraction: 1.0)
//        img1.draw(at: NSPoint(x: img1.size.width, y: 0), from: .zero, operation: .sourceOver, fraction: 1.0)
//
//        newImage.unlockFocus()
//        
//        return newImage
//    }
}


// MARK: ── PageControllerView
struct PageControllerView: NSViewControllerRepresentable {
    @ObservedObject var model: ImageViewerModel            // モデルの状態を監視し、UIと同期させる
    let holder: ControllerHolder                           // 外部からNSPageControllerを操作するためのホルダー
    
    func makeNSViewController(context: Context) -> NSPageController {
        let pc = NSPageController()                        // NSPageControllerインスタンス生成
        holder.controller = pc                             // ホルダーに保持させて外部から操作可能に
        pc.delegate = context.coordinator                  // デリゲートにCoordinatorをセット
        pc.arrangedObjects = model.images                  // ページに表示する画像URLリストを設定
        pc.transitionStyle = .horizontalStrip              // 横スライド式のページ遷移スタイル
        pc.selectedIndex = model.currentIndex              // 現在の画像インデックスを初期設定
        return pc                                          // 作成したページコントローラーを返す
    }
    
    func updateNSViewController(_ pc: NSPageController, context: Context) {
        // ViewModelの画像リストと異なる場合は更新
        if pc.arrangedObjects as? [URL] != model.images {
            pc.arrangedObjects = model.images
        }
        
        // 選択中のインデックスをViewModelと同期
        if pc.selectedIndex != model.currentIndex {
            pc.completeTransition() // 既存のトランジションを完了（同期ミス対策）
            pc.selectedIndex = model.currentIndex // インデックスを更新
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self) // Coordinator（デリゲート）を生成
    }
    
// MARK: ── Coordinatorクラス（NSPageControllerDelegate対応）
    class Coordinator: NSObject, NSPageControllerDelegate {
        let parent: PageControllerView // 親View構造体への参照
        
        init(parent: PageControllerView) {
            self.parent = parent
        }
        
        // ページ毎のViewController（画像ビュー）を生成
        func pageController(_ pc: NSPageController, viewControllerForIdentifier _: String) -> NSViewController {
            let vc = NSViewController()
            let iv = NSImageView()                             // 画像表示用View
            iv.imageScaling = .scaleProportionallyUpOrDown    // 比率維持しながら拡大縮小
            iv.autoresizingMask = [.width, .height]           // 親に合わせてリサイズ
            iv.wantsLayer = true                              // レイヤーを有効化（変形用）
            
            // ジェスチャ対応（拡大・パン・ダブルクリック）
            iv.addGestureRecognizer(NSMagnificationGestureRecognizer(target: self, action: #selector(handlePinch(_:))))
            let dbl = NSClickGestureRecognizer(target: self, action: #selector(handleDoubleClick(_:)))
            dbl.numberOfClicksRequired = 2
            iv.addGestureRecognizer(dbl)
            iv.addGestureRecognizer(NSPanGestureRecognizer(target: self, action: #selector(handlePan(_:))))
            vc.view = iv
            return vc
        }
        
        // 各オブジェクトに紐づく識別子
        func pageController(_: NSPageController, identifierFor _: Any) -> String {
            "ImageVC" // 固定文字列で識別
        }
        
        // ページ準備（画像の読み込みと初期設定）
        func pageController(_ pc: NSPageController, prepare vc: NSViewController, with object: Any?) {
//            guard let url = object as? URL,
//                  let iv = vc.view as? NSImageView,
//                  let layer = iv.layer else { return }
//            
//            //iv.image = NSImage(contentsOf: url) // 対象画像をロード
//            
//            //print(parent.model.spreadViewMode)
//            
//            let idx = parent.model.images.firstIndex(of: url) ?? 0
//            let nextURL = (idx + 1 < parent.model.images.count) ? parent.model.images[idx + 1] : nil
//
//            print(parent.model.spreadViewMode)
//            print(nextURL as Any)
            
            //iv.image = parent.model.makeSpreadImagesec(current: url, next: nextURL)

//            switch parent.model.spreadViewMode {
//            case .none:
//                iv.image = NSImage(contentsOf: url)
//                return
//            case .previousLeft:
//                iv.image = parent.model.makeSpreadImagesec(current: url, next: nextURL)
//                return
//            case .nextRight:
//                iv.image = parent.model.makeSpreadImage(current: url, next: nextURL)
//                return
//            }
            
            
///////////////////
            guard let url = object as? URL,
                     let iv = vc.view as? NSImageView,
                     let layer = iv.layer else { return }

               let model = parent.model
               let index = model.images.firstIndex(of: url) ?? 0

               // 差し替え画像があればそれを優先表示
               if let override = model.temporaryImageOverrides[url] {
                   iv.image = override
               } else {
                   iv.image = NSImage(contentsOf: url)
               }
///////////////////
            
            
            
            
            
            
            layer.anchorPoint = CGPoint(x: 0.5, y: 0.5) // 拡大/縮小の中心を設定
            layer.position = CGPoint(x: iv.bounds.midX, y: iv.bounds.midY) // 中央に配置
            layer.setAffineTransform(.identity) // 変形リセット
            
            DispatchQueue.main.async {
                self.parent.model.scale = 1.0     // 拡大率リセット
                self.parent.model.offset = .zero  // オフセットリセット
            }
        }
        
        // 遷移完了時にインデックスをViewModelに反映
        func pageController(_ pc: NSPageController, didTransitionTo object: Any) {
            if let idx = pc.arrangedObjects.firstIndex(where: { ($0 as? URL) == (object as? URL) }) {
                DispatchQueue.main.async {
                    self.parent.model.currentIndex = idx // インデックスを更新
                    self.parent.model.clearOverrides() // 合成を解除

                }
            }
        }
        
        

        // 拡大処理（ピンチ）
        @objc func handlePinch(_ g: NSMagnificationGestureRecognizer) {
            // 対象のビューが NSImageView であることを確認し、CALayer を取得
            guard let iv = g.view as? NSImageView,
                  let layer = iv.layer else { return }
            
            // ピンチ操作の発生位置を取得（ビュー内座標）
            let loc = g.location(in: iv)
            
            // ビューのサイズ（frame ではなく bounds）を取得
            let b = iv.bounds
            
            DispatchQueue.main.async {
                // ピンチの中心を基準とした拡大を行うため、アンカーポイントを算出
                // 画像内のどの位置を中心に拡大縮小するか（0.0〜1.0）
                let ax = loc.x / b.width
                let ay = loc.y / b.height
                
                // layer の拡大縮小の基準点を変更（デフォルトは中央 0.5, 0.5）
                layer.anchorPoint = CGPoint(x: ax, y: ay)
                
                // 実際に anchor を中心に変形が適用されるよう位置を調整
                layer.position = CGPoint(x: loc.x, y: loc.y)
                
                // 拡大率を更新：現在のスケール × ピンチ倍率（+1される点に注意）
                let ns = self.parent.model.scale * (1 + g.magnification)
                
                // スケールの範囲を制限（例：0.5〜5倍）
                self.parent.model.scale = min(max(ns, 0.5), 5.0)
                
                // 計算した変形をビューに反映
                self.applyTransform(iv: iv)
                
                // このジェスチャーでの拡大率は使い終わったのでリセット
                g.magnification = 0
            }
        }
        
        // ダブルクリックで拡大・リセット
        @objc func handleDoubleClick(_ g: NSClickGestureRecognizer) {
            guard let iv = g.view as? NSImageView,
                  let layer = iv.layer else { return }
            let loc = g.location(in: iv)
            let b = iv.bounds
            
            DispatchQueue.main.async {
                let ax = loc.x / b.width
                let ay = loc.y / b.height
                layer.anchorPoint = CGPoint(x: ax, y: ay)
                layer.position = CGPoint(x: loc.x, y: loc.y)
                
                // 拡大の段階的切り替え
                switch self.parent.model.scale {
                case ..<1.5: self.parent.model.scale = 2.0
                case ..<3.0: self.parent.model.scale = 4.0
                default:
                    self.parent.model.scale = 1.0
                    self.parent.model.offset = .zero
                    layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
                    layer.position = CGPoint(x: iv.bounds.midX, y: iv.bounds.midY)
                }
                self.applyTransform(iv: iv)
            }
        }
        
        // パン（画像移動）
        @objc func handlePan(_ g: NSPanGestureRecognizer) {
            guard let iv = g.view as? NSImageView else { return }
            let tr = g.translation(in: iv)
            g.setTranslation(.zero, in: iv)
            
            DispatchQueue.main.async {
                self.parent.model.offset.width += tr.x
                self.parent.model.offset.height += tr.y
                self.applyTransform(iv: iv)
            }
        }
        // パン（画像移動）
        private func applyTransform(iv: NSImageView) {
            // 現在のスケール（拡大率）を取得（例: 1.0 = 等倍, 2.0 = 2倍拡大）
            let s = parent.model.scale
            
            // 現在のオフセット（パンによる移動量）を取得（CGSize型、x/y 方向の移動）
            let o = parent.model.offset
            
            // 単位行列（変形なしの状態）を初期値として変形を構築
            var t = CGAffineTransform.identity
            
            // 平行移動を先に適用（x方向 o.width, y方向 o.height）
            t = t.translatedBy(x: o.width, y: o.height)
            
            // スケーリング（拡大縮小）を適用（x,y 同率拡大）
            t = t.scaledBy(x: s, y: s)
            
            // 計算した変形行列を NSImageView の CALayer に反映
            iv.layer?.setAffineTransform(t)
        }
        
    }
    
    // PageControllerを外部から操作するためのホルダークラス
    class ControllerHolder { weak var controller: NSPageController? }
}

// MARK: ── キーボード左右キー入力を受け取る NSView（NSView のサブクラス）
class KeyHandlingView: NSView {
    // キーイベントを処理するクロージャ（親Viewから渡される）
    var onKey: (NSEvent) -> Bool = { _ in false }
    
    // このビューがファーストレスポンダ（キーイベントの受け取り手）になれるようにする
    override var acceptsFirstResponder: Bool { true }
    
    // このビューがウィンドウに追加された時にファーストレスポンダにする
    override func viewDidMoveToWindow() {
        window?.makeFirstResponder(self) // 自身をキーイベントの受け手に設定
    }
    
    // キーが押された時に呼ばれる
    override func keyDown(with event: NSEvent) {
        // クロージャで処理されなければスーパークラスにフォールバック
        if onKey(event) == false {
            super.keyDown(with: event)
        }
    }
}

// SwiftUI から macOS の NSView を埋め込むラッパー
// MARK: ── キーボードイベント（特に←→キー）を処理して、NSPageController のページ移動を可能にする
struct KeyboardHandlingRepresentable: NSViewRepresentable {
    let holder: PageControllerView.ControllerHolder // NSPageController へのアクセス用ホルダ（弱参照）
    
    // 実際の NSView（KeyHandlingView）を生成する
    func makeNSView(context: Context) -> NSView {
        let v = KeyHandlingView() // NSView のサブクラス（カスタム）を作成
        
        // キーイベントが発生したときの処理を定義
        
        v.onKey = { ev in
            guard let pc = holder.controller else { return false }
            let currentIndex = pc.selectedIndex
            let count = pc.arrangedObjects.count
            
            switch ev.keyCode {
            case 123: // ← 左キー
                                
                if currentIndex > 0 {
                    pc.navigateBack(nil)
                } else {
                    showAlert(message: "先頭の画像です")
                }
                return true
                
            case 124: // → 右キー
                if currentIndex < count - 1 {
                    pc.navigateForward(nil)
                } else {
                    showAlert(message: "最後の画像です")
                }
                return true
                
            default:
                return false
            }
        }
        return v // NSView を SwiftUI に返す
    }
    
    
    func showAlert(message: String) {
        // 通知用ウィンドウを作成（タイトルバーなし）
        let alertWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 80),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        
        alertWindow.isReleasedWhenClosed = false
        alertWindow.level = .floating
        alertWindow.backgroundColor = .clear
        alertWindow.isOpaque = false
        alertWindow.hasShadow = true
        alertWindow.ignoresMouseEvents = true // ユーザー操作無効化
        alertWindow.collectionBehavior = [.canJoinAllSpaces, .transient] // 全画面でも表示可能
        alertWindow.alphaValue = 0.0
        
        // メッセージ表示用ラベル
        let textField = NSTextField(labelWithString: message)
        textField.alignment = .center
        textField.font = NSFont.systemFont(ofSize: 16, weight: .medium)
        textField.textColor = NSColor.white
        textField.backgroundColor = .clear
        textField.isBezeled = false
        textField.drawsBackground = false
        
        // 背景ビュー（角丸・黒半透明）
        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 80))
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.8).cgColor
        contentView.layer?.cornerRadius = 14
        textField.frame = contentView.bounds.insetBy(dx: 20, dy: 20)
        contentView.addSubview(textField)
        
        alertWindow.contentView = contentView
        
        // 画面中央に配置
        if let screenFrame = NSScreen.main?.frame {
            let x = (screenFrame.width - alertWindow.frame.width) / 2
            let y = (screenFrame.height - alertWindow.frame.height) / 2
            alertWindow.setFrameOrigin(NSPoint(x: x, y: y))
        }
        
        alertWindow.makeKeyAndOrderFront(nil)
        
        // フェードイン
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            alertWindow.animator().alphaValue = 1.0
        }
        
        // 自動フェードアウト & 閉じる（1.5秒後）
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.3
                alertWindow.animator().alphaValue = 0.0
            }, completionHandler: {
                alertWindow.close()
            })
        }
    }
    
    // SwiftUI の View 更新タイミングで呼ばれる（ここでは何もしない）
    func updateNSView(_ nsView: NSView, context: Context) {
        // 状態更新が必要なときの処理を書くが、ここでは不要
    }
}

// MARK: ── ウィンドウリサイズを検出
struct WindowResizeObserver: NSViewRepresentable {
    var onResizeEnded: () -> Void
    
    class Coordinator {
        var workItem: DispatchWorkItem?
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                NotificationCenter.default.addObserver(
                    forName: NSWindow.didResizeNotification,
                    object: window,
                    queue: .main
                ) { _ in
                    // 以前の処理をキャンセル
                    context.coordinator.workItem?.cancel()
                    
                    // 一定時間後に onResizeEnded を呼び出す
                    let item = DispatchWorkItem {
                        onResizeEnded()
                    }
                    
                    context.coordinator.workItem = item
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: item)
                }
            }
        }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}




// MARK: ── メインビュー（SwiftUIのメイン画面）

struct ContentView: View {
    //モデル（画像一覧や状態）を監視
    @ObservedObject var model: ImageViewerModel
    
    //PageControllerのインスタンス保持用（ビューの再構築を避ける）
    private let holder = PageControllerView.ControllerHolder()
    
    //表示内容の強制リフレッシュ用バインディング
    @Binding var viewerID: UUID
    
    var body: some View {
        VStack(spacing: 3) { // 全体を縦方向に積む（余白3pt）
            
            // --- ヘッダーエリア（フォルダ選択 + サムネイル + インジケータ）
            HStack(spacing: 6) {
                
                //フォルダ選択ボタン
                Button("フォルダを選択") {
                    // macOS の標準フォルダ選択ダイアログ
                    let panel = NSOpenPanel()
                    panel.canChooseDirectories = true
                    panel.canChooseFiles = false
                    panel.allowsMultipleSelection = false
                    panel.prompt = "選択"
                    
                    if panel.runModal() == .OK, let url = panel.url {
                        //状態をリセット（表示画像・スケール・オフセット）
                        model.currentIndex = 0
                        model.scale = 1.0
                        model.offset = .zero
                        
                        //画像読み込み（非同期でサムネイルも生成）
                        model.loadImagesFromDirectory(url)
                        
                        //viewerIDを更新してPageControllerをリフレッシュ
                        viewerID = UUID()
                    }
                }
                .controlSize(.small) // macOS風小サイズボタン
                
                // --- サムネイル表示エリア
                if !model.images.isEmpty {
                    ScrollViewReader { scrollProxy in
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                // 全画像を列挙
                                ForEach(Array(model.images.enumerated()), id: \.offset) { index, url in
                                    let isSelected = (index == model.currentIndex)
                                    
                                    if let thumb = model.thumbnail(for: url) {
                                        //サムネイル表示（選択時は青枠）
                                        Image(nsImage: thumb)
                                            .resizable()
                                            .aspectRatio(contentMode: .fill)
                                            .frame(width: 40, height: 40)
                                            .clipped()
                                            .cornerRadius(4)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 4)
                                                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
                                            )
                                            .id(index) //スクロール用ID
                                            .onTapGesture {
                                                model.currentIndex = index
                                                //選択時にスクロールセンターへ
                                                withAnimation {
                                                    scrollProxy.scrollTo(index, anchor: .center)
                                                }
                                            }
                                    } else {
                                        //サムネイル未生成時のプレースホルダ
                                        Rectangle()
                                            .fill(Color.gray.opacity(0.1))
                                            .frame(width: 40, height: 40)
                                            .cornerRadius(4)
                                            .id(index)
                                    }
                                }
                            }
                        }
                        .frame(height: 42)
                        .onChange(of: model.currentIndex) { oldIndex, newIndex in
                            // currentIndex が変化した瞬間
                            withAnimation {
                                scrollProxy.scrollTo(newIndex, anchor: .center)
                            }
                        }
                    }
                }
                
                //現在インデックス/総画像数 の表示
                Text(model.images.isEmpty
                     ? "画像なし"
                     : "\(model.currentIndex + 1) / \(model.images.count)")
                .font(.caption)
                .controlSize(.small)
                
                //見開き表示モードを切り替えます
                Button(action: {
                    let idx = model.currentIndex
                    guard idx > 0 else { return }
                    let current = model.images[idx]
                    let previous = model.images[idx - 1]
                    if let combined = model.makeSpreadImage(current: current, next: previous) {
                    //if let combined = model.makeSpreadImage(current: previous, next: current) {

                        model.overrideImage(for: current, with: combined)
                        // ✅ SwiftUI側からViewを再生成
                        viewerID = UUID()
                    }
                }) {
                    Text("見開き")
                }
                .controlSize(.small)
                .help("この画像だけ一時的に見開きで表示します")

                
                
                
                
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(minHeight: 28)
            
            Divider() // 水平の境界線
            
            // --- メイン画像表示エリア
            if model.images.isEmpty {
                //画像なしのメッセージ表示
                Text("画像が読み込まれていません")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .foregroundColor(.secondary)
            } else {
                ZStack {
                    //画像のページング表示（NSPageController）
                    PageControllerView(model: model, holder: holder)
                    //キーボード対応（← → で前後画像）
                    KeyboardHandlingRepresentable(holder: holder)
                        .allowsHitTesting(false)
                    //ウィンドウリサイズを検出して viewerID を更新
                    WindowResizeObserver {
                        viewerID = UUID() //リサイズ終了後に一度だけ再構築
                        //print("リサイズ終了後に一度だけ再構築")
                    }
                    .frame(width: 0, height: 0)
                }
                .id(viewerID) //viewerID変更でViewを強制更新
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 600, minHeight: 400) // ウィンドウ最小サイズ
    }
}




