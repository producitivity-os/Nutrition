import ProductivityUI
import SwiftUI

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

    var body: some View {
        Group {
            if let image = MediaService.image(for: asset) {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                ZStack {
                    Color.accentColor.opacity(0.1)
                    LucideIcon(name: .image, size: 24).foregroundStyle(.tint)
                }
            }
        }
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

struct EmptyCollectionView: View {
    let icon: LucideIconName
    let title: String
    let message: String

    var body: some View {
        ProductivityEmptyState(icon: icon, title: title, message: message)
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
