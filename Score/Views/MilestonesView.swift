import SwiftUI

struct MilestonesView: View {
    @Environment(ScoreStore.self) private var store
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Semester Milestones")
                        .font(.system(.largeTitle, design: .serif))
                        .fontWeight(.bold)
                    Text("Special guests, exhibitions, and scheduling details.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                let categories = ["Guests", "Exhibition", "Special Schedule", "Running Threads"]
                ForEach(categories, id: \.self) { category in
                    let items = store.constitution.milestones.filter { $0.category == category }
                    if !items.isEmpty {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack(spacing: 8) {
                                Image(systemName: iconForCategory(category))
                                    .foregroundStyle(.blue)
                                Text(category)
                                    .font(.title2.bold())
                            }
                            
                            VStack(spacing: 12) {
                                ForEach(items) { item in
                                    HStack(spacing: 16) {
                                        Text(item.dateString)
                                            .font(.caption.bold())
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 6)
                                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                                            .frame(width: 140, alignment: .leading)
                                        
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(item.title)
                                                .font(.body.bold())
                                            if !item.detail.isEmpty {
                                                Text(item.detail)
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                        Spacer()
                                    }
                                    .padding(14)
                                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                                }
                            }
                            .padding(.leading, 8)
                        }
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 850)
        }
        .background(
            LinearGradient(colors: [.indigo.opacity(0.08), .purple.opacity(0.12), .clear], startPoint: .topLeading, endPoint: .bottomTrailing)
        )
    }
    
    private func iconForCategory(_ category: String) -> String {
        switch category {
        case "Guests": return "person.2.fill"
        case "Exhibition": return "photo.on.rectangle.angled"
        case "Special Schedule": return "calendar.badge.clock"
        case "Running Threads": return "arrow.3.trianglepath"
        default: return "star.fill"
        }
    }
}
