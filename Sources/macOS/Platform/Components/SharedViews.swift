import AppKit
import ProductivityUI
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct PageHeader: View {
    let eyebrow: String
    let title: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        ProductivityPageHeader(title, eyebrow: eyebrow, actionTitle: actionTitle, action: action)
    }
}

struct MediaThumbnail: View {
    let asset: MediaAsset?
    var cornerRadius: CGFloat = 12
    var contentMode: ContentMode = .fill

    var body: some View {
        GeometryReader { bounds in
            Group {
                if let image = MediaService.image(for: asset) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: contentMode)
                } else {
                    ZStack {
                        Color.accentColor.opacity(0.1)
                        LucideIcon(name: .image, size: 24).foregroundStyle(.tint)
                    }
                }
            }
            .frame(width: bounds.size.width, height: bounds.size.height)
            .clipped()
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

struct EmptyCollectionView: View {
    let icon: LucideIconName
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            LucideIcon(name: icon, size: 22)
                .foregroundStyle(NutritionTheme.accent)
                .frame(width: 42, height: 42)
                .background(NutritionTheme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(message).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(15)
        .frame(maxWidth: 430, alignment: .leading)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 15))
        .accessibilityElement(children: .combine)
    }
}

struct EditableMediaTile: View {
    @Environment(\.modelContext) private var context
    @Binding var asset: MediaAsset?
    var title = "Choose Image"
    var size = CGSize(width: 132, height: 116)
    @State private var importing = false
    @State private var error: String?

    var body: some View {
        Button { importing = true } label: {
            ZStack(alignment: .bottom) {
                MediaThumbnail(asset: asset, cornerRadius: 15)
                HStack(spacing: 5) {
                    Image(systemName: asset == nil ? "photo.badge.plus" : "photo.badge.arrow.down")
                    Text(asset == nil ? title : "Replace")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 9).padding(.vertical, 6)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(8)
            }
            .frame(width: size.width, height: size.height)
            .overlay { RoundedRectangle(cornerRadius: 15).stroke(.secondary.opacity(0.2)) }
        }
        .buttonStyle(.plain)
        .focusable()
        .help("Choose an image, or focus this tile and press Command-V")
        .contextMenu {
            Button("Paste Image") { pasteImage() }
            if asset != nil { Button("Remove Image", role: .destructive) { asset = nil } }
        }
        .onPasteCommand(of: [.image]) { _ in pasteImage() }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.image]) { result in
            do {
                let url = try result.get()
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                asset = try MediaService.importImage(from: url, context: context)
            } catch { self.error = error.localizedDescription }
        }
        .alert("Image could not be imported", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }

    private func pasteImage() {
        guard let image = NSPasteboard.general.readObjects(forClasses: [NSImage.self])?.first as? NSImage,
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let data = bitmap.representation(using: .png, properties: [:]) else {
            error = "The clipboard does not contain a supported image."
            return
        }
        do { asset = try MediaService.importImage(data: data, name: "Pasted image.png", mimeType: "image/png", context: context) }
        catch { self.error = error.localizedDescription }
    }
}

enum NutritionFormat {
    static func amount(_ value: Double?, unit: String, maximumDigits: Int = 1) -> String {
        guard let value else { return "—" }
        return "\(value.formatted(.number.precision(.fractionLength(0...maximumDigits)))) \(unit)"
    }

    static func currency(minor: Int?, code: String?) -> String {
        guard let minor, let code else { return "Price unavailable" }
        return (Double(minor) / 100).formatted(.currency(code: code))
    }
}

let weekdayNames = Calendar.current.weekdaySymbols.enumerated().map { index, value in
    (index: (index + 6) % 7, name: value)
}.sorted { $0.index < $1.index }.map(\.name)
