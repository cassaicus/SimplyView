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
                Button("FolderSelect") {
                    // macOS の標準フォルダ選択ダイアログ
                    let panel = NSOpenPanel()
                    panel.canChooseDirectories = true
                    panel.canChooseFiles = false
                    panel.allowsMultipleSelection = false
                    panel.prompt = "Select"
                    
                    if panel.runModal() == .OK, let url = panel.url {
                        //状態をリセット（表示画像・スケール・オフセット）
                        model.currentIndex = 0
                        model.scale = 1.0
                        model.offset = .zero
                        //model.anchorPoint = CGPoint(x: 0.5, y: 0.5)
                        //画像読み込み（非同期でサムネイルも生成）
                        model.loadImagesFromDirectory(url)
                        //viewerIDを更新してPageControllerをリフレッシュ
                        //viewerID = UUID()
                    }
                }
                // macOS風小サイズボタン
                .controlSize(.small)
                // 横幅を直接指定
                .frame(width: 85)
                
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
                                            //スクロール用ID
                                            .id(index)
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
                     ? "NO image"
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
                    Text("📖")
                }
                .controlSize(.small)
                .help("This image will be temporarily displayed in a two-page spread.")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(minHeight: 28)
            
            // --- メイン画像表示エリア
            if model.images.isEmpty {
                //画像なしのメッセージ表示
                Text("Image not loaded.")
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

extension Array {
    subscript(safe index: Int) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}

struct SettingsView: View {
    @ObservedObject var model: ImageViewerModel
    @AppStorage("reverseSpread") var reverseSpread = false
    @AppStorage("reverseArrowKeys") var reverseKeyboard = false
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Settings")
                .font(.title2)
                .bold()
            
            Divider()
            
            // ここを HStack にして横並びに
            HStack(alignment: .top, spacing: 20) {
                GroupBox(label: Text("How to Use")) {
                    VStack(alignment: .leading, spacing: 6) {
                        
                        VStack(alignment: .leading, spacing: 6) {
                            Text("・← / →: Show previous/next image")
                            Text("・Right to go forward, left to go back (can be reversed)")
                            Text("・Mouse drag: Move the image")
                            Text("・Double click: Zoom (2x, 4x, reset)")
                            Text("・[📖] moves the previous image to the right Displays the current image on the left (can be reversed) Will be canceled when you move forward/backward")
                            Text("・Use [Select] to load a file in one of the formats below")
                            Text("  Load file Supported formats: jpg, jpeg, png, gif, bmp, webp")

                            
                        }
                        .font(.system(size: 13))
                        .padding(.vertical, 5)
                        
                        
                    }
                    .font(.system(size: 13))
                    .padding(.vertical, 5)
                }
                .frame(maxWidth: .infinity)
                
                GroupBox(label: Text("Options")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Reverse ← → arrow key direction", isOn: $reverseKeyboard)
                        Toggle("Display page spread left-right reversed", isOn: $reverseSpread)
                    }
                    .padding(.top, 4)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal)
            
            //Spacer()
            
            HStack {
                Spacer()
                Button("close") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        // 2カラムを想定して十分な幅を指定
        .frame(width: 650, height: 465)
    }
}
