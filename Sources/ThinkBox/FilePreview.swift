import QuickLookUI
import SwiftUI

struct FilePreview: View {
    let url: URL

    var body: some View {
        VStack(spacing: 0) {
            if FileManager.default.fileExists(atPath: url.path) {
                QuickLookSurface(url: url)
                HStack {
                    Spacer()
                    Button("Abrir en app externa", line: "arrow.up.forward.app") {
                        NSWorkspace.shared.open(url)
                    }.buttonStyle(ChromeButtonStyle())
                }.padding(10)
            } else {
                ContentUnavailableView("Archivo no disponible", systemImage: "doc.questionmark")
            }
        }
    }
}

private struct QuickLookSurface: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> QLPreviewView {
        let preview = QLPreviewView(frame: .zero, style: .normal)!
        preview.autostarts = true
        preview.previewItem = url as NSURL
        return preview
    }

    func updateNSView(_ preview: QLPreviewView, context: Context) {
        if preview.previewItem?.previewItemURL != url { preview.previewItem = url as NSURL }
    }
}
