import Foundation

enum AccountRole: String, Codable, CaseIterable, Identifiable {
    case instructor, student
    var id: Self { self }
    var label: String { rawValue.capitalized }
}

struct Account: Codable, Equatable {
    var id: UUID
    var name: String
    var email: String
    var role: AccountRole
    var token: String?
}

struct ChatMessage: Identifiable, Codable, Equatable {
    let id: UUID
    var role: String
    var text: String
    var createdAt: Date
}

