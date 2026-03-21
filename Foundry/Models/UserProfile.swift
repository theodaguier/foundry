import Foundation

struct UserProfile: Codable, Identifiable, Sendable {
    let id: UUID
    var email: String
    var displayName: String?
    var avatarURL: String?
    var plan: UserPlan
    var pluginsGenerated: Int
    var createdAt: Date

    enum UserPlan: String, Codable, Sendable {
        case free
        case pro
    }

    enum CodingKeys: String, CodingKey {
        case id
        case email
        case displayName = "display_name"
        case avatarURL = "avatar_url"
        case plan
        case pluginsGenerated = "plugins_generated"
        case createdAt = "created_at"
    }
}
