import AppKit
import SwiftUI

enum LucideIconName: String {
    case archive, calendar, circle, coins, copy, image, leaf, pencil, plus, ruler, save, search, settings, star, store, utensils, x
    case checkCircle = "check-circle-2"
    case forkKnife = "fork-knife"
    case gripVertical = "grip-vertical"
    case imagePlus = "image-plus"
    case listOrdered = "list-ordered"
    case mapPin = "map-pin"
    case trash = "trash-2"

    var fallbackSymbol: String {
        switch self {
        case .archive: "archivebox"
        case .calendar: "calendar"
        case .circle: "circle"
        case .coins: "dollarsign.circle"
        case .copy: "doc.on.doc"
        case .image, .imagePlus: "photo"
        case .leaf: "leaf"
        case .pencil: "pencil"
        case .plus: "plus"
        case .ruler: "ruler"
        case .save: "square.and.arrow.down"
        case .search: "magnifyingglass"
        case .settings: "gearshape"
        case .star: "star"
        case .store: "storefront"
        case .utensils, .forkKnife: "fork.knife"
        case .x: "xmark"
        case .checkCircle: "checkmark.circle"
        case .gripVertical: "line.3.horizontal"
        case .listOrdered: "list.number"
        case .mapPin: "mappin"
        case .trash: "trash"
        }
    }
}

struct LucideIcon: View {
    let name: LucideIconName
    var size: CGFloat = 16

    var body: some View {
        Group {
            if let url = Bundle.main.url(forResource: name.rawValue, withExtension: "svg", subdirectory: "Lucide"),
               let image = NSImage(contentsOf: url) {
                Image(nsImage: image).resizable().renderingMode(.template).scaledToFit()
            } else {
                Image(systemName: name.fallbackSymbol).resizable().scaledToFit()
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
