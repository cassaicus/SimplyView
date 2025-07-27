import SwiftUI                   // SwiftUI を使って UI を構築します
import AppKit                    // macOS 固有の AppKit 機能を使用します

// MARK: ContentView SwiftUIのメイン
struct ContentView: View {
    //モデル（画像一覧や状態）を監視
    @ObservedObject var model: ImageViewerModel
    //PageControllerのインスタンス保持用（ビューの再構築を避ける）
    private let holder = PageControllerView.ControllerHolder()
    //表示内容の強制リフレッシュ用バインディング
    @Binding var viewerID: UUID
    
    //@State private var showSettings = false
    @Binding var showSettings: Bool
    
    
    //画面構成
    var body: some View {
        // 全体を縦方向に積む（余白3pt）
        VStack(spacing: 3) {
            // --- ヘッダーエリア（フォルダ選択 + サムネイル + インジケータ）
            HStack(spacing: 6) {
                // --- フォルダ選択ボタン
                Button("Folder") {
                    // macOS の標準フォルダ選択ダイアログ
                    let panel = NSOpenPanel()
                    panel.canChooseDirectories = true
                    panel.canChooseFiles = false
                    panel.allowsMultipleSelection = false
                    panel.prompt = "Choice"
                    
                    if panel.runModal() == .OK, let url = panel.url {
                        //状態をリセット（表示画像・スケール・オフセット）
                        model.currentIndex = 0
                        model.scale = 1.0
                        model.offset = .zero
                        //model.anchorPoint = CGPoint(x: 0.5, y: 0.5)
                        //画像読み込み（非同期でサムネイルも生成）
                        model.loadImagesFromDirectory(url)
                        //viewerIDを更新してPageControllerをリフレッシュ
                        viewerID = UUID()
                    }
                }
                // macOS風小サイズボタン
                .controlSize(.small)
                
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
                
                // --- 総画像数 の表示エリア
                Text(model.images.isEmpty
                     ? "画像なし"
                     : "\(model.currentIndex + 1) / \(model.images.count)")
                .font(.caption)
                .controlSize(.small)
                
                // --- 見開き表示モードを切り替えボタン
                Button(action: {
                    let idx = model.currentIndex
                    guard idx > 0 else { return }
                    let current = model.images[idx]
                    let previous = model.images[idx - 1]
                    if let combined = model.makeSpreadImage(current: current, next: previous) {
                        //画像を上書き
                        model.overrideImage(for: current, with: combined)
                        //SwiftUI側からViewを再生成
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
                    KeyboardHandlingRepresentable(holder: holder, model: model)
                        .allowsHitTesting(false)
                    //ウィンドウリサイズを検出して viewerID を更新
                    WindowResizeObserver {
                        //リサイズ終了後に一度だけ再構築
                        viewerID = UUID()
                        //print("リサイズ終了後に一度だけ再構築")
                    }
                    .frame(width: 0, height: 0)
                }
                //viewerID変更でViewを強制更新
                .id(viewerID)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(model: model)
        }
        // ウィンドウ最小サイズ
        .frame(minWidth: 600, minHeight: 400)
    }
}

struct SettingsView: View {
    @ObservedObject var model: ImageViewerModel
    @AppStorage("reverseSpread") var reverseSpread: Bool = false
    @AppStorage("reverseArrowKeys") var reverseKeyboard: Bool = false
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("設定")
                .font(.title2)
                .bold()
            
            Divider()
            
            GroupBox(label: Text("操作方法")) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("・← / →：前後の画像を表示")
                    Text("・右で進む、左で戻る（逆設定可能）")
                    Text("・マウスドラッグ：画像を移動")
                    Text("・ダブルクリック：拡大(2倍,4倍,リセット)")
                    Text("・「見開き」は一つ前の画像を右に、")
                    Text("　　表示中の画像を左に表示（逆設定可能）")
                    Text("　　進むか戻るで解除されます。")
                    Text("・[フォルダを選択]で下記の形式で指定する")
                    Text("　　ファイルを読み込みます。")
                    Text("対応拡張子　jpg,jpeg,png,gif,bmp,webp")

                }
                .font(.system(size: 13))
                .padding(.vertical, 5)
            }
            .padding(.horizontal)
            
            
            Divider()
            
            GroupBox(label: Text("オプション")) {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("← → キーの方向を逆にする", isOn: $reverseKeyboard)
                    Toggle("見開きを左右逆に表示", isOn: $reverseSpread)
                }
                .padding(.top, 4)
            }
            .padding(.horizontal)

            Spacer()
            
            HStack {
                Spacer()
                Button("閉じる") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 315, height: 515)
    }
}
