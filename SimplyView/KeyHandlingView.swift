import SwiftUI                   // SwiftUI を使って UI を構築します
import AppKit                    // macOS 固有の AppKit 機能を使用します

// MARK: キーボード左右キー入力を受け取る NSView（NSView のサブクラス）
class KeyHandlingView: NSView {
    // キーイベントを処理するクロージャ（親Viewから渡される）
    var onKey: (NSEvent) -> Bool = { _ in false }
    // このビューがファーストレスポンダ（キーイベントの受け取り手）になれるようにする
    override var acceptsFirstResponder: Bool { true }
    // このビューがウィンドウに追加された時にファーストレスポンダにする
    override func viewDidMoveToWindow() {
        // 自身をキーイベントの受け手に設定
        window?.makeFirstResponder(self)
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
// MARK: キーボードイベント（特に←→キー）を処理して、NSPageController のページ移動を可能にする
struct KeyboardHandlingRepresentable: NSViewRepresentable {
    // NSPageController へのアクセス用ホルダ（弱参照）
    let holder: PageControllerView.ControllerHolder
    //
    let model: ImageViewerModel // ← 追加
    // 実際の NSView（KeyHandlingView）を生成する
    func makeNSView(context: Context) -> NSView {
        // NSView のサブクラス（カスタム）を作成
        let v = KeyHandlingView()
        // キーイベントが発生したときの処理を定義
        v.onKey = { ev in
            guard let pc = holder.controller else { return false }
            let currentIndex = pc.selectedIndex
            let count = pc.arrangedObjects.count
            // reverseKeyboard 設定を確認
            let isReversed = model.reverseKeyboard
            
            switch ev.keyCode {
            case 123: // ← 左キー
                if isReversed {
                    // 右キーとして処理
                    if currentIndex < count - 1 {
                        pc.navigateForward(nil)
                    } else if let win = v.window {
                        showAutoDismissAlert(message: "last image", in: win)
                    }
                } else {
                    if currentIndex > 0 {
                        pc.navigateBack(nil)
                    } else if let win = v.window {
                        showAutoDismissAlert(message: "first image", in: win)
                    }
                }
                return true
            case 124: // → 右キー
                if isReversed {
                    // 左キーとして処理
                    if currentIndex > 0 {
                        pc.navigateBack(nil)
                    } else if let win = v.window {
                        showAutoDismissAlert(message: "first image", in: win)
                    }
                } else {
                    if currentIndex < count - 1 {
                        pc.navigateForward(nil)
                    } else if let win = v.window {
                        showAutoDismissAlert(message: "last image", in: win)
                    }
                }
                return true
            default:
                return false
            }
        }
        // NSView を SwiftUI に返す
        return v
    }
    
    // アラート関数：1.5秒で自動的に消える通知ウィンドウを表示（タイトルバーなし）
    func showAutoDismissAlert(message: String, in window: NSWindow) {
        
        // 通知用の小さなウィンドウを生成（タイトルバーなし、透明）
        let alertWindow = NSWindow(
            // サイズ指定
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 80),
            // 枠なしウィンドウ
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        // ウィンドウを閉じたときに解放しないように設定（使い回し可能）
        alertWindow.isReleasedWhenClosed = false
        // 他のウィンドウの上に浮かぶように設定
        alertWindow.level = .floating
        // 背景透明にする設定
        alertWindow.backgroundColor = .clear
        alertWindow.isOpaque = false
        // ドロップシャドウを表示
        alertWindow.hasShadow = true
        // マウス操作を無効化（背後のUIと干渉しないようにする）
        alertWindow.ignoresMouseEvents = true
        // 一時的なウィンドウとして扱い、Mission Control などでも浮いたまま表示
        alertWindow.collectionBehavior = [.transient]
        // --- メッセージ用ラベル（非編集の NSTextField）を作成
        let textField = NSTextField(labelWithString: message)
        textField.alignment = .center
        textField.font = NSFont.systemFont(ofSize: 16, weight: .medium)
        textField.textColor = NSColor.white
        textField.backgroundColor = .clear
        textField.drawsBackground = false
        // --- 背景ビュー（黒半透明 + 角丸）を作成
        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 80))
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.8).cgColor
        contentView.layer?.cornerRadius = 14
        // ラベルの配置（周囲に余白を入れて中央寄せ）
        textField.frame = contentView.bounds.insetBy(dx: 20, dy: 20)
        contentView.addSubview(textField)
        // アラートウィンドウの中身として設定
        alertWindow.contentView = contentView
        // 呼び出し元ウィンドウの中央にアラートウィンドウを配置
        let parentFrame = window.frame
        let alertSize = alertWindow.frame.size
        let x = parentFrame.origin.x + (parentFrame.size.width - alertSize.width) / 2
        let y = parentFrame.origin.y + (parentFrame.size.height - alertSize.height) / 2
        alertWindow.setFrameOrigin(NSPoint(x: x, y: y))
        // 初期状態は透明（アニメーションでフェードイン）
        alertWindow.alphaValue = 0.0
        // ウィンドウを画面上に表示
        //alertWindow.makeKeyAndOrderFront(nil)
        // ウィンドウを画面上に表示 変更後（警告なし）
        NSApp.mainWindow?.addChildWindow(alertWindow, ordered: .above)
        // フェードインのアニメーション（0.2秒で不透明に）
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            alertWindow.animator().alphaValue = 1.0
        }
        // 1.5秒後にフェードアウトして自動的に閉じる
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
