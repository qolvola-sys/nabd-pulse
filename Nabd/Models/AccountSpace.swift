import Foundation

#if MUTABAA
/// مساحة مستقلة داخل «المتابعة»: لكل مساحة اسمها وحساباتها وترتيبها.
/// الحسابات تُحفظ داخل المساحة نفسها حتى يبقى الترتيب اليدوي ثابتًا.
struct AccountSpace: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var accounts: [Account]
    var createdAt: String

    init(
        id: String = UUID().uuidString,
        name: String,
        accounts: [Account] = [],
        createdAt: String = ISO8601DateFormatter.nabd.string(from: Date())
    ) {
        self.id = id
        self.name = name
        self.accounts = accounts
        self.createdAt = createdAt
    }
}
#endif
