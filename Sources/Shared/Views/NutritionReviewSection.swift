import Foundation
import ProductivityUI
import SwiftUI

private struct NutritionReviewRecord: Codable, Identifiable {
    let id: UUID
    let rating: Int
    let note: String
    let createdAt: Date
}

struct NutritionReviewSection: View {
    @AppStorage private var storage: Data
    @State private var rating = 5
    @State private var note = ""

    init(targetID: UUID) {
        _storage = AppStorage(wrappedValue: Data(), "nutrition.reviews.\(targetID.uuidString)")
    }

    private var reviews: [NutritionReviewRecord] {
        (try? JSONDecoder().decode([NutritionReviewRecord].self, from: storage)) ?? []
    }

    private var distribution: [RatingDistributionData] {
        (1...5).map { value in RatingDistributionData(rating: value, count: reviews.count { $0.rating == value }) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            RatingsSpreadCard(ratings: distribution, title: "Reviews")
            VStack(alignment: .leading, spacing: 8) {
                Text("Add a review").font(.headline)
                HStack(spacing: 5) {
                    ForEach(1...5, id: \.self) { value in
                        Button { rating = value } label: {
                            Image(systemName: value <= rating ? "star.fill" : "star").foregroundStyle(.yellow)
                        }.buttonStyle(.plain)
                    }
                }
                TextField("Notes (optional)", text: $note, axis: .vertical).lineLimit(1...3)
                Button("Save Review") { addReview() }.buttonStyle(.borderedProminent)
            }
            .padding(12)
            .background(.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func addReview() {
        var values = reviews
        values.append(NutritionReviewRecord(id: UUID(), rating: rating, note: note.trimmingCharacters(in: .whitespacesAndNewlines), createdAt: .now))
        storage = (try? JSONEncoder().encode(values)) ?? storage
        note = ""
    }
}
