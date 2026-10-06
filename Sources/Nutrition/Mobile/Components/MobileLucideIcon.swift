import SwiftUI
import UIKit

struct MobileLucideIcon: View {
    let name: String
    var fallback: String

    init(_ name: String, fallback: String) {
        self.name = name
        self.fallback = fallback
    }

    var body: some View {
        if let url = Bundle.main.url(forResource: name, withExtension: "svg", subdirectory: "Lucide"),
           let image = UIImage(contentsOfFile: url.path)?.withRenderingMode(.alwaysTemplate) {
            Image(uiImage: image).resizable().scaledToFit()
        } else {
            Image(systemName: fallback).resizable().scaledToFit()
        }
    }
}
