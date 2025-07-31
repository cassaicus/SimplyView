
import SwiftUI

struct ToolsCommands: Commands {
    // 画像表示に関する状態を管理するモデル
    @ObservedObject var model: ImageViewerModel
    // 表示の強制リフレッシュに使う識別子（外部バインディング
    @Binding var viewerID: UUID
    
    var body: some Commands {
        // "Tools" という名前のメニューを作成
        CommandMenu("Tools") {
            // フォルダ選択ボタン
            Button("Folder Select") {
                // フォルダ選択ダイアログを生成
                let panel = NSOpenPanel()
                // ディレクトリ選択を許可
                panel.canChooseDirectories = true
                // ファイル選択は無効化
                panel.canChooseFiles = false
                // 複数選択を不可
                panel.allowsMultipleSelection = false
                // ダイアログのボタンラベルを指定
                panel.prompt = "Select"
                
                if panel.runModal() == .OK, let url = panel.url {
                    // 表示インデックスをリセット
                    model.currentIndex = 0
                    // 拡大率をリセット
                    model.scale = 1.0
                    // パン位置をリセット
                    model.offset = .zero
                    // フォルダから画像を読み込む
                    model.loadImagesFromDirectory(url)
                    // 表示を強制的に更新
                    viewerID = UUID()
                }
            }
            // メニュー内に区切り線を挿入
            Divider()
            // 拡大ボタン
            Button("+") {
                // 拡大率を1.2倍に変更
                model.scale *= 1.2
                // 現在のImageViewがあれば、中心点をウィンドウ中央に設定
                if let iv = model.currentImageView, let layer = iv.layer {
                    layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
                    layer.position = CGPoint(x: iv.bounds.midX, y: iv.bounds.midY)
                    // 変形を反映
                    model.applyTransform(iv: iv)
                }
                //viewerID = UUID()
                // 念のため再実行
                if let iv = model.currentImageView{
                    model.applyTransform(iv: iv)
                }
            }
            .disabled({
                // 現在画像が無効なときはボタンをグレーアウト
                !(model.images.indices.contains(model.currentIndex))
            }())
            // 縮小ボタン
            Button("-") {
                // 20% 縮小
                model.scale /= 1.2
                // ウィンドウ中央を中心にスケーリング
                if let iv = model.currentImageView, let layer = iv.layer {
                    layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
                    layer.position = CGPoint(x: iv.bounds.midX, y: iv.bounds.midY)
                    // 変形を反映
                    model.applyTransform(iv: iv)
                }
                
                //viewerID = UUID()
                // 念のため再実行
                if let iv = model.currentImageView{
                    model.applyTransform(iv: iv)
                }
            }
            .disabled({
                // 現在画像が無効なときはボタンをグレーアウト
                !(model.images.indices.contains(model.currentIndex))
            }())
            
            // 実サイズに合わせて拡大率を設定するボタン
            Button("RealScale") {
                if let iv = model.currentImageView,
                   let rep = iv.image?.representations.first {
                    // 実ピクセル数
                    let pixelWidth = CGFloat(rep.pixelsWide)
                    // 実際に画面に表示されている幅
                    let viewWidth = iv.bounds.width
                    // 実スケールを算出
                    let realScale = viewWidth != 0 ? pixelWidth / viewWidth : 1.0
                    // 拡大率を設定
                    model.scale = realScale
                    // スケールを画面中央基準で適用
                    if let iv = model.currentImageView, let layer = iv.layer {
                        layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
                        layer.position = CGPoint(x: iv.bounds.midX, y: iv.bounds.midY)
                        model.applyTransform(iv: iv)
                    }
                    
                    // 念のため再実行
                    model.applyTransform(iv: iv)
                }
            }
            .disabled({
                // 現在画像が無効なときはボタンをグレーアウト
                !(model.images.indices.contains(model.currentIndex))
            }())
            // メニュー内に区切り線を挿入
            Divider()
            // 見開き合成
            Button("Facing pages") {
                let idx = model.currentIndex
                // 先頭ページでは無効
                guard idx > 0 else { return }
                // 現在の画像
                let current = model.images[idx]
                // 前の画像
                let previous = model.images[idx - 1]
                if let combined = model.makeSpreadImage(current: current, next: previous) {
                    // 合成画像で上書き
                    model.overrideImage(for: current, with: combined)
                    // 表示更新
                    viewerID = UUID()
                }
            }
            // 無効化条件: 前の画像が存在しない or どちらかのファイルが存在しない
            .disabled({
                let idx = model.currentIndex
                guard idx > 0 else { return true }
                let current = model.images[idx]
                let previous = model.images[idx - 1]
                return !(FileManager.default.fileExists(atPath: current.path) &&
                         FileManager.default.fileExists(atPath: previous.path))
            }())
            // メニュー内に区切り線を挿入
            Divider()
            // 現在のフォルダをFinderで開くボタン
            Button("Open the current folder in Finder") {
                let folderURL = model.images[model.currentIndex].deletingLastPathComponent()
                // macOSのFinderでフォルダを開く
                NSWorkspace.shared.open(folderURL)
            }
            // 現在画像が無効なときはボタンをグレーアウト
            .disabled({
                guard model.images.indices.contains(model.currentIndex) else { return true }
                let folderURL = model.images[model.currentIndex].deletingLastPathComponent()
                var isDir: ObjCBool = false
                return !FileManager.default.fileExists(atPath: folderURL.path, isDirectory: &isDir) || !isDir.boolValue
            }())
        }
    }
}
