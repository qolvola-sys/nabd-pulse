import Foundation

#if MUTABAA
/// مجموعة داخل مساحة «المتابعة».
/// العضوية محفوظة في `AccountSpace.groupMembership`،
/// والترتيب داخل المجموعة يتبع ترتيب حسابات المساحة.
struct AccountGroup: Identifiable, Codable, Hashable {
    /// أقصى عدد حسابات في المجموعة الواحدة.
    static let capacity = 7

    var id: String
    var name: String
    var createdAt: String

    init(
        id: String = UUID().uuidString,
        name: String,
        createdAt: String = ISO8601DateFormatter.nabd.string(from: Date())
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
    }
}
#endif
