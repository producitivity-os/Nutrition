import AppKit
import CryptoKit
import Foundation
import SwiftData
import UniformTypeIdentifiers

enum MediaService {
    @MainActor
    static func importImage(from url: URL, context: ModelContext) throws -> MediaAsset {
        let data = try Data(contentsOf: url)
        let mimeType = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        return try importImage(data: data, name: url.lastPathComponent, mimeType: mimeType, context: context)
    }

    @MainActor
    static func importImage(data: Data, name: String, mimeType: String, context: ModelContext) throws -> MediaAsset {
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let descriptor = FetchDescriptor<MediaAsset>(predicate: #Predicate { $0.contentHash == hash })
        if let existing = try context.fetch(descriptor).first { return existing }
        guard let image = NSImage(data: data) else { throw CocoaError(.fileReadCorruptFile) }
        let thumbnail = thumbnailData(for: image)
        let asset = MediaAsset(contentHash: hash, originalName: name, mimeType: mimeType, originalData: data, thumbnailData: thumbnail, width: Int(image.size.width), height: Int(image.size.height))
        context.insert(asset)
        return asset
    }

    static func image(for asset: MediaAsset?, thumbnail: Bool = true) -> NSImage? {
        guard let asset else { return nil }
        return NSImage(data: thumbnail ? (asset.thumbnailData ?? asset.originalData) : asset.originalData)
    }

    @MainActor
    private static func thumbnailData(for image: NSImage) -> Data? {
        let maximum: CGFloat = 512
        let scale = min(maximum / max(image.size.width, 1), maximum / max(image.size.height, 1), 1)
        let size = NSSize(width: max(1, image.size.width * scale), height: max(1, image.size.height * scale))
        let thumbnail = NSImage(size: size)
        thumbnail.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(origin: .zero, size: size), from: NSRect(origin: .zero, size: image.size), operation: .copy, fraction: 1)
        thumbnail.unlockFocus()
        guard let tiff = thumbnail.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.82])
    }
}
