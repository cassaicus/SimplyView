
import SwiftUI

struct ToolsCommands: Commands {
    @ObservedObject var model: ImageViewerModel
    @Binding var viewerID: UUID  // 表示の強制更新用

    var body: some Commands {
        CommandMenu("Tools") {

            // フォルダ選択ボタン
            Button("Folder Select") {
                let panel = NSOpenPanel()
                panel.canChooseDirectories = true
                panel.canChooseFiles = false
                panel.allowsMultipleSelection = false
                panel.prompt = "Select"

                if panel.runModal() == .OK, let url = panel.url {
                    model.currentIndex = 0
                    model.scale = 1.0
                    model.offset = .zero
                    model.loadImagesFromDirectory(url)
                    viewerID = UUID()  // 表示更新
                }
            }

            Divider()
            // 拡大ボタン
            Button("+") {
                
                model.scale *= 1.2 // 20% 拡大
                
                if let iv = model.currentImageView, let layer = iv.layer {
                    layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
                    layer.position = CGPoint(x: iv.bounds.midX, y: iv.bounds.midY)
                    model.applyTransform(iv: iv)
                }
                
                //viewerID = UUID()
                if let iv = model.currentImageView{
                    model.applyTransform(iv: iv)
                }
            }
            .disabled({
                // 現在の画像が存在しない場合は無効化
                !(model.images.indices.contains(model.currentIndex))
            }())

            
            Button("-") {
                model.scale /= 1.2 // 20% 縮小
                
                if let iv = model.currentImageView, let layer = iv.layer {
                    layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
                    layer.position = CGPoint(x: iv.bounds.midX, y: iv.bounds.midY)
                    model.applyTransform(iv: iv)
                }
                
                
                //viewerID = UUID()
                if let iv = model.currentImageView{
                    model.applyTransform(iv: iv)
                }
            }
            .disabled({
                // 現在の画像が存在しない場合は無効化
                !(model.images.indices.contains(model.currentIndex))
            }())

            
            Button("RealScale") {
                if let iv = model.currentImageView,
                   let rep = iv.image?.representations.first {

                    let pixelWidth = CGFloat(rep.pixelsWide)
                    let viewWidth = iv.bounds.width // ← 実際に画面に表示されている幅

                    let realScale = viewWidth != 0 ? pixelWidth / viewWidth : 1.0
                    model.scale = realScale
                    
                    if let iv = model.currentImageView, let layer = iv.layer {
                        layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
                        layer.position = CGPoint(x: iv.bounds.midX, y: iv.bounds.midY)
                        model.applyTransform(iv: iv)
                    }
                    
                    
                    model.applyTransform(iv: iv)
                }
            }
            .disabled({
                !(model.images.indices.contains(model.currentIndex))
            }())
            
            Divider()
            
            
            // 見開き合成ボタン
            Button("Facing pages") {
                let idx = model.currentIndex
                guard idx > 0 else { return }
                let current = model.images[idx]
                let previous = model.images[idx - 1]
                if let combined = model.makeSpreadImage(current: current, next: previous) {
                    model.overrideImage(for: current, with: combined)
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
            
            Divider()
            
            // 現在のフォルダをFinderで開くボタン
            Button("Open the current folder in Finder") {
                let folderURL = model.images[model.currentIndex].deletingLastPathComponent()
                NSWorkspace.shared.open(folderURL)
            }
            .disabled({
                guard model.images.indices.contains(model.currentIndex) else { return true }
                let folderURL = model.images[model.currentIndex].deletingLastPathComponent()
                var isDir: ObjCBool = false
                return !FileManager.default.fileExists(atPath: folderURL.path, isDirectory: &isDir) || !isDir.boolValue
            }())
        }
    }
}
