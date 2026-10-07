import ProductivityUI
import SwiftUI

struct MobileLucideIcon: View {
    let name: String
    var fallback: String

    init(_ name: String, fallback: String) {
        self.name = name
        self.fallback = fallback
    }

    var body: some View {
        if let icon = LucideIconName(rawValue: name) {
            LucideIcon(name: icon)
        } else {
            Image(systemName: fallback).resizable().scaledToFit()
        }
    }
}
