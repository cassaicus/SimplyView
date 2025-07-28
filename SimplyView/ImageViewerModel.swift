import SwiftUI                   // SwiftUI を使って UI を構築します
import AppKit                    // macOS 固有の AppKit 機能を使用します

// MARK: ImageViewerModel
class ImageViewerModel: ObservableObject {
    // シングルトンインスタンス（外部から共有的にアクセス）
    static let shared = ImageViewerModel()
    
    // 読み込まれた画像ファイルのURL配列（Viewがリアルタイムに監視）
    @Published var images: [URL] = []
    // 現在表示中の画像インデックス
    @Published var currentIndex = 0
    // 現在の拡大率（ピンチ/ダブルクリックで変更）
    @Published var scale: CGFloat = 1.0
    // 画像のオフセット（パン操作で使用）
    @Published var offset: CGSize = .zero
    // 読み込み中かどうか（インジケータ制御などで利用）
    @Published var isLoading = false
    
    //見開き表示用の一時的な合成画像差し替え
    @Published var temporaryImageOverrides: [URL: NSImage] = [:]
    
    // 設定オプション（AppStorageで永続化）
    // 見開きの制御
    @AppStorage("reverseSpread") var reverseSpread: Bool = false
    // キーボード制御
    @AppStorage("reverseArrowKeys") var reverseKeyboard: Bool = false
    
    //上書き
    func overrideImage(for url: URL, with image: NSImage) {
        temporaryImageOverrides[url] = image
        objectWillChange.send() // 強制UI更新
    }
    //合成を解除
    func clearOverrides() {
        temporaryImageOverrides.removeAll()
    }
    
    // URLとNSImageを結びつけるサムネイルキャッシュ
    private var _thumbnailCache: [URL: NSImage] = [:]
    // 外部からは読み取り専用でアクセス
    var thumbnailCache: [URL: NSImage] {
        _thumbnailCache
    }
    
    func setThumbnail(_ image: NSImage, for url: URL) {
        // キャッシュに登録
        _thumbnailCache[url] = image
        DispatchQueue.main.async {
            // SwiftUI に手動で変更通知（UI更新トリガー）
            self.objectWillChange.send()
        }
    }
    // キャッシュから該当URLのサムネイルを返す
    func thumbnail(for url: URL) -> NSImage? {
        return _thumbnailCache[url]
    }
    
    // フォルダから画像を読みだす
    func loadImagesFromDirectory(_ folder: URL) {
        // 対応画像拡張子配列
        let allowed = ["jpg","jpeg","png","gif","bmp","webp"]
        
        DispatchQueue.global(qos: .userInitiated).async {
            if let urls = try? FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
            ) {
                let filtered = urls
                    .filter { allowed.contains($0.pathExtension.lowercased()) }
                //Finder風の自然順ソート
                    .sorted {
                        $0.lastPathComponent
                            .localizedStandardCompare($1.lastPathComponent)
                        == .orderedAscending
                    }
                
                // メインスレッドでUI更新を行うためにディスパッチ
                DispatchQueue.main.async {
                    // 画像がない時は停止
                    if filtered.isEmpty {
                        // 画像が見つからなかった場合
                        //サムネイルクリア
                        self._thumbnailCache.removeAll()
                        // ダミーURLを1件だけ設定してクラッシュ回避
                        let dummyURL = URL(fileURLWithPath: "/dev/null") // macOSでは無害なパス
                        self.images = [dummyURL]
                        self.currentIndex = 0
                        self.scale = 1.0
                        self.offset = .zero
                        self.isLoading = false
                        //アラート表示
                        let alert = NSAlert()
                        alert.messageText = "画像が見つかりません"
                        alert.informativeText = "このフォルダには画像ファイルが含まれていません。"
                        alert.alertStyle = .warning
                        alert.runModal()
                        
                        return
                    }
                    // フィルタ済画像リストをViewに反映
                    self.images = filtered
                    // 表示位置を先頭に
                    self.currentIndex = 0
                    // 拡大リセット
                    self.scale = 1.0
                    // オフセットリセット
                    self.offset = .zero
                    // サムネイルキャッシュをクリア
                    self._thumbnailCache.removeAll()
                    // 読み込み中に切り替え
                    self.isLoading = true
                }
                //リサイズしてサムネイルを作成
                for url in filtered {
                    if let image = NSImage(contentsOf: url) {
                        // 40x40のサイズにリサイズしてサムネイルを作成
                        let thumb = self.resizeImage(image: image, size: NSSize(width: 40, height: 40))
                        DispatchQueue.main.async {
                            // サムネイルを設定
                            self.setThumbnail(thumb, for: url)
                        }
                    }
                    // 負荷軽減のために少し待つ
                    Thread.sleep(forTimeInterval: 0.01)
                }
                
                DispatchQueue.main.async {
                    // 読み込み終了
                    self.isLoading = false
                }
            }
        }
    }
    // リサイズ
    func resizeImage(image: NSImage, size: NSSize) -> NSImage {
        guard let rep = image.bestRepresentation(for: NSRect(origin: .zero, size: size), context: nil, hints: nil) else {
            // リサイズできない場合は元画像を返す
            return image
        }
        let resizedImage = NSImage(size: size)
        // 描画開始
        resizedImage.lockFocus()
        // 指定サイズに描画
        rep.draw(in: NSRect(origin: .zero, size: size))
        // 描画終了
        resizedImage.unlockFocus()
        return resizedImage
    }
    // 2つの画像URL（current, next）を横に合成して、1枚の見開き画像を生成する関数
    func makeSpreadImage(current: URL, next: URL?) -> NSImage? {
        // current の画像を読み込み（必須）し、next の画像はオプショナルで読み込む
        guard let img1 = NSImage(contentsOf: current),
              let img2 = next.flatMap({ NSImage(contentsOf: $0) }) else {
            // どちらかが読み込めなければ処理中止
            return nil
        }
        // 横幅は2枚分を加算、高さはどちらか高い方を使用（高さの合成はしない）
        let totalWidth = img1.size.width + img2.size.width
        let maxHeight = max(img1.size.height, img2.size.height)
        // 合成後の画像サイズを設定（横に2枚分、縦は高い方）
        let size = NSSize(width: totalWidth, height: maxHeight)
        // 新しい空のNSImageを作成（この中に合成画像を描く）
        let newImage = NSImage(size: size)
        // 描画を開始（この時点で描画コンテキストが開かれる）
        newImage.lockFocus()
        
        //左右を入れ替え
        if reverseSpread {
            // img2（current）を左側（x=0）に描画
            img2.draw(at: NSPoint(x: 0, y: 0), from: .zero, operation: .sourceOver, fraction: 1.0)
            // img1（next）を右側（x=img2の幅）に描画
            img1.draw(at: NSPoint(x: img2.size.width, y: 0), from: .zero, operation: .sourceOver, fraction: 1.0)
        } else {
            // img1（current）を左側（x=0）に描画
            img1.draw(at: NSPoint(x: 0, y: 0), from: .zero, operation: .sourceOver, fraction: 1.0)
            // img2（next）を右側（x=img1の幅）に描画
            img2.draw(at: NSPoint(x: img1.size.width, y: 0), from: .zero, operation: .sourceOver, fraction: 1.0)
        }
        
        // 描画を終了（描画コンテキストを閉じる）
        newImage.unlockFocus()
        // 合成結果の画像を返す
        return newImage
    }
}

// MARK: PageControllerView
struct PageControllerView: NSViewControllerRepresentable {
    // モデルの状態を監視し、UIと同期させる
    @ObservedObject var model: ImageViewerModel
    // 外部からNSPageControllerを操作するためのホルダー
    let holder: ControllerHolder
    
    func makeNSViewController(context: Context) -> NSPageController {
        // NSPageControllerインスタンス生成
        let pc = NSPageController()
        // ホルダーに保持させて外部から操作可能に
        holder.controller = pc
        // デリゲートにCoordinatorをセット
        pc.delegate = context.coordinator
        // ページに表示する画像URLリストを設定
        pc.arrangedObjects = model.images
        // 横スライド式のページ遷移スタイル
        pc.transitionStyle = .horizontalStrip
        // 現在の画像インデックスを初期設定
        pc.selectedIndex = model.currentIndex
        // 作成したページコントローラーを返す
        return pc
    }
    
    func updateNSViewController(_ pc: NSPageController, context: Context) {
        // ViewModelの画像リストと異なる場合は更新
        if pc.arrangedObjects as? [URL] != model.images {
            pc.arrangedObjects = model.images
        }
        
        // 選択中のインデックスをViewModelと同期
        if pc.selectedIndex != model.currentIndex {
            // 既存のトランジションを完了（同期ミス対策）
            pc.completeTransition()
            // インデックスを更新
            pc.selectedIndex = model.currentIndex
        }
    }
    
    func makeCoordinator() -> Coordinator {
        // Coordinator（デリゲート）を生成
        Coordinator(parent: self)
    }
    
    // MARK: Coordinatorクラス（NSPageControllerDelegate対応）
    class Coordinator: NSObject, NSPageControllerDelegate {
        // 親View構造体への参照
        let parent: PageControllerView
        
        init(parent: PageControllerView) {
            self.parent = parent
        }
        
        // ページ毎のViewController（画像ビュー）を生成
        func pageController(_ pc: NSPageController, viewControllerForIdentifier _: String) -> NSViewController {
            // 画像表示用View
            let vc = NSViewController()
            let iv = NSImageView()
            // 比率維持しながら拡大縮小
            iv.imageScaling = .scaleProportionallyUpOrDown
            // 親に合わせてリサイズ
            iv.autoresizingMask = [.width, .height]
            // レイヤーを有効化（変形用）
            iv.wantsLayer = true
            // ジェスチャ対応（拡大・パン・ダブルクリック）
            iv.addGestureRecognizer(NSMagnificationGestureRecognizer(target: self, action: #selector(handlePinch(_:))))
            let dbl = NSClickGestureRecognizer(target: self, action: #selector(handleDoubleClick(_:)))
            dbl.numberOfClicksRequired = 2
            iv.addGestureRecognizer(dbl)
            iv.addGestureRecognizer(NSPanGestureRecognizer(target: self, action: #selector(handlePan(_:))))
            vc.view = iv
            return vc
        } //funcEnd
        
        // 各オブジェクトに紐づく識別子
        func pageController(_: NSPageController, identifierFor _: Any) -> String {
            "ImageVC" // 固定文字列で識別
        } //funcEnd
        
        // ページが表示される直前に呼ばれる処理（画像の読み込みや表示設定などを行う）
        func pageController(_ pc: NSPageController, prepare vc: NSViewController, with object: Any?) {
            // 表示対象の画像URLと、ViewControllerのNSImageView・そのレイヤーを取得
            guard let url = object as? URL,
                  let iv = vc.view as? NSImageView,
                  // いずれか取得できなければ表示処理中止
                  let layer = iv.layer else { return }
            
            // ViewModel（画像一覧や状態管理）を取得
            let model = parent.model
            // 現在表示しようとしている画像のインデックス
            _ = model.images.firstIndex(of: url) ?? 0
            
            // temporaryImageOverrides に登録された「一時的な合成画像」があればそちらを優先して表示
            if let override = model.temporaryImageOverrides[url] {
                iv.image = override
            } else {
                // 通常の画像を読み込んで表示
                iv.image = NSImage(contentsOf: url)
            }
            
            // ▼ 以下は表示ビューの初期化処理（変形リセットなど） ▼
            // 拡大/縮小や回転の中心点を画像中央に設定（レイヤーのアンカーポイント）
            layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            // 画像ビュー（iv）の中央に画像レイヤーを配置
            layer.position = CGPoint(x: iv.bounds.midX, y: iv.bounds.midY)
            // 変形をすべてリセット（スケール・回転・移動など）
            layer.setAffineTransform(.identity)
            // メインスレッドで、拡大率や移動オフセットの状態をリセット（SwiftUI側と同期）
            DispatchQueue.main.async {
                // 拡大率リセット
                self.parent.model.scale = 1.0
                // パン（移動）リセット
                self.parent.model.offset = .zero
            }
        } //funcEnd
        
        // 遷移完了時にインデックスをViewModelに反映
        func pageController(_ pc: NSPageController, didTransitionTo object: Any) {
            if let idx = pc.arrangedObjects.firstIndex(where: { ($0 as? URL) == (object as? URL) }) {
                DispatchQueue.main.async {
                    // インデックスを更新
                    self.parent.model.currentIndex = idx
                    // 合成を解除
                    self.parent.model.clearOverrides()
                }
            }
        } //funcEnd
        
        // 拡大処理（ピンチ）
        @objc func handlePinch(_ g: NSMagnificationGestureRecognizer) {
            // 対象のビューが NSImageView であることを確認し、CALayer を取得
            guard let iv = g.view as? NSImageView,
                  let layer = iv.layer else { return }
            // ピンチ操作の発生位置を取得（ビュー内座標）
            let loc = g.location(in: iv)
            // ビューのサイズ（frame ではなく bounds）を取得
            let b = iv.bounds
            
            // メインスレッドでUIの状態を更新
            DispatchQueue.main.async {
                // ピンチの中心を基準とした拡大を行うため、アンカーポイントを算出
                // 画像内のどの位置を中心に拡大縮小するか（0.0〜1.0）
                // 横方向の比率（0.0〜1.0）
                let ax = loc.x / b.width
                // 縦方向の比率（0.0〜1.0）
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
        } //funcEnd
        
        // ダブルクリック時に拡大・縮小を切り替える処理（段階的ズーム操作）
        @objc func handleDoubleClick(_ g: NSClickGestureRecognizer) {
            // ジェスチャーの対象が NSImageView かどうか確認し、レイヤーを取得
            guard let iv = g.view as? NSImageView,
                  let layer = iv.layer else { return }
            // ダブルクリックが発生した位置（ビュー内座標）を取得
            let loc = g.location(in: iv)
            // ビューのサイズを取得（座標比率を計算するために使用）
            let b = iv.bounds
            
            // メインスレッドでUIの状態を更新
            DispatchQueue.main.async {
                // アンカーポイント（拡大・縮小の中心）をクリック位置の比率で設定
                // 横方向の比率（0.0〜1.0）
                let ax = loc.x / b.width
                // 縦方向の比率（0.0〜1.0）
                let ay = loc.y / b.height
                layer.anchorPoint = CGPoint(x: ax, y: ay)
                // レイヤーの位置をクリック位置に合わせて移動（見た目の中心点がズレないよう調整）
                layer.position = CGPoint(x: loc.x, y: loc.y)
                // 現在の拡大率に応じて段階的に切り替え（等倍 → 2倍 → 4倍 → リセット）
                switch self.parent.model.scale {
                case ..<1.5:
                    // 1.0 → 2.0 に拡大
                    self.parent.model.scale = 2.0
                case ..<3.0:
                    // 2.0 → 4.0 にさらに拡大
                    self.parent.model.scale = 4.0
                default:
                    // それ以上の場合はリセット（等倍に戻す）
                    self.parent.model.scale = 1.0
                    // パン（移動）もリセット
                    self.parent.model.offset = .zero
                    // 中心点を画面中央に戻す（リセット時は中央から拡大）
                    layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
                    layer.position = CGPoint(x: iv.bounds.midX, y: iv.bounds.midY)
                }
                // 拡大率や位置などの変形をレイヤーに反映
                self.applyTransform(iv: iv)
            }
        } //funcEnd
        
        // パン（画像をドラッグで移動）操作を処理する関数
        @objc func handlePan(_ gesture: NSPanGestureRecognizer) {
            guard let imageView = gesture.view as? NSImageView,
                  let window = imageView.window,
                  let contentView = window.contentView,
                  let displayArea = imageView.superview,// PageControllerView内の画像エリア
                  let layer = imageView.layer else { return }
            
            
            let displayBoundsInWindow = displayArea.convert(displayArea.bounds, to: nil)
            
            let translation = gesture.translation(in: imageView)
            gesture.setTranslation(.zero, in: imageView)
            
            DispatchQueue.main.async {
                let proposedOffset = CGSize(
                    width: self.parent.model.offset.width + translation.x,
                    height: self.parent.model.offset.height + translation.y
                )
                
                // 仮 offset を適用して transform
                let originalTransform = layer.affineTransform()
                var transform = originalTransform
                
                transform.tx = proposedOffset.width
                transform.ty = proposedOffset.height
                
                let model = self.parent.model
                if let image = imageView.image {
                    let imageSize = image.size
                    let zoomScale = model.scale
                    
                    // 拡大後の画像サイズ
                    let zoomedImageWidth = imageSize.width * zoomScale
                    let zoomedImageHeight = imageSize.height * zoomScale
                    
                    // ウィンドウと拡大画像のフィット比率（fitRatio は見かけ上の補正倍率）
                    let fitRatio = min(displayBoundsInWindow.width / zoomedImageWidth,
                                       displayBoundsInWindow.height / zoomedImageHeight)
                    
                    // 見かけ上の画像サイズ
                    let displayedImageWidth = zoomedImageWidth * fitRatio * zoomScale
                    let displayedImageHeight = zoomedImageHeight * fitRatio * zoomScale
                    
                    let halfWindowWidth = displayBoundsInWindow.width / 2
                    let halfWindowHeight = displayBoundsInWindow.height / 2
                    
                    let halfImageWidth = displayedImageWidth / 2
                    let halfImageHeight = displayedImageHeight / 2
                    
                    // ベースのマージン（等倍基準）
                    let baseMarginX = displayBoundsInWindow.width - halfWindowWidth - halfImageWidth
                    let baseMarginY = displayBoundsInWindow.height - halfWindowHeight - halfImageHeight
                    
                    // 拡大率に応じた追加マージン
                    var additionalMarginX: CGFloat = 0.0
                    var additionalMarginY: CGFloat = 0.0
                    
                    if zoomScale > 1.0 && zoomScale <= 2.0 {
                        additionalMarginX = halfWindowWidth
                        additionalMarginY = halfWindowHeight
                    } else if zoomScale > 1.0 && zoomScale <= 3.0 {
                        additionalMarginX = halfWindowWidth * 2
                        additionalMarginY = halfWindowHeight * 2
                    } else if zoomScale > 1.0 && zoomScale <= 4.0 {
                        additionalMarginX = halfWindowWidth * 3
                        additionalMarginY = halfWindowHeight * 3
                    }
                    
                    // 画像の見かけ上サイズの10%を余白として設定
                    let imageMarginX = displayedImageWidth * 0.1
                    let imageMarginY = displayedImageHeight * 0.1
                    // 方向に応じて transform.tx に補正値を加減
                    if transform.tx > 0 {
                        transform.tx += baseMarginX + additionalMarginX + imageMarginX
                    } else {
                        transform.tx -= baseMarginX + additionalMarginX + imageMarginX
                    }
                    // 方向に応じて transform.ty に補正値を加減
                    if transform.ty > 0 {
                        transform.ty += baseMarginY + additionalMarginY + imageMarginY + 84.0
                    } else {
                        transform.ty -= baseMarginY + additionalMarginY + imageMarginY
                    }
                    // 仮 transform を imageView に適用
                    layer.setAffineTransform(transform)
                    let transformedFrame = layer.frame
                    // 元に戻す
                    layer.setAffineTransform(originalTransform)
                    
                    let contentBounds = contentView.bounds
                    
                    if contentBounds.intersects(transformedFrame) {
                        // はみ出してないので offset 更新
                        self.parent.model.offset = proposedOffset
                        self.applyTransform(iv: imageView)
                    } else {
                        // はみ出すので移動しない
                        NSSound.beep()
                    }
                }
            }
        } //funcEnd
        
        // レイヤーへの反映（画像を実際に動かす）関数
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
        } //funcEnd
    }
    // PageControllerを外部から操作するためのホルダークラス
    class ControllerHolder { weak var controller: NSPageController? }
}

// MARK: ウィンドウリサイズ
//検出後、サイズ変更終了後にコールバックを実行する View
struct WindowResizeObserver: NSViewRepresentable {
    // リサイズ完了後に呼び出されるクロージャ（呼び出し元で処理を指定）
    var onResizeEnded: () -> Void
    // SwiftUI 用 Coordinator クラス（リサイズ処理を管理）
    class Coordinator {
        // DispatchWorkItem を使ってリサイズ後の遅延実行を管理
        var workItem: DispatchWorkItem?
    }
    // Coordinator のインスタンスを生成
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    // SwiftUI → NSView に変換する本体
    func makeNSView(context: Context) -> NSView {
        let view = NSView() // 空のNSViewを生成（表示は不要）
        // 非同期でウィンドウが取得できるタイミングを待って処理を開始
        DispatchQueue.main.async {
            if let window = view.window {
                // NSWindow のリサイズ通知を監視
                NotificationCenter.default.addObserver(
                    forName: NSWindow.didResizeNotification, // ウィンドウがリサイズされたとき
                    object: window,
                    queue: .main
                ) { _ in
                    // 前回の処理が残っていればキャンセル（連続イベント対策）
                    context.coordinator.workItem?.cancel()
                    // 一定時間後にリサイズ終了として onResizeEnded を実行する
                    let item = DispatchWorkItem {
                        onResizeEnded()
                    }
                    // 現在の WorkItem を保存
                    context.coordinator.workItem = item
                    // 0.3秒後に処理を実行（リサイズが続かなければ）
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: item)
                }
            }
        }
        // 作成した NSView を返す（画面上には見えない）
        return view
    }
    // SwiftUI による View 更新時の処理（今回は不要なので空実装）
    func updateNSView(_ nsView: NSView, context: Context) {}
}
