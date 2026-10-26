import Foundation

#if MUTABAA
/// مساحة مستقلة داخل «المتابعة»: لكل مساحة اسمها وحساباتها وترتيبها.
/// الحسابات تُحفظ داخل المساحة نفسها حتى يبقى الترتيب اليدوي ثابتًا.
/// لكل مساحة مجموعات محفوظة بسعة ٧ حسابات، وعضوية كل حساب محفوظة بالمعرّف.
struct AccountSpace: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var accounts: [Account]
    var createdAt: String
    /// مجموعات المساحة بترتيب ظهورها في القائمة.
    var groups: [AccountGroup]
    /// معرّف الحساب -> معرّف المجموعة.
    var groupMembership: [String: String]

    init(
        id: String = UUID().uuidString,
        name: String,
        accounts: [Account] = [],
        createdAt: String = ISO8601DateFormatter.nabd.string(from: Date()),
        groups: [AccountGroup] = [],
        groupMembership: [String: String] = [:]
    ) {
        self.id = id
        self.name = name
        self.accounts = accounts
        self.createdAt = createdAt
        self.groups = groups
        self.groupMembership = groupMembership
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case accounts
        case createdAt
        case groups
        case groupMembership
    }

    /// فك الترميز مع دعم النسخ القديمة التي لا تحتوي مجموعات.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        accounts = try container.decode([Account].self, forKey: .accounts)
        createdAt = try container.decode(String.self, forKey: .createdAt)
        groups = try container.decodeIfPresent([AccountGroup].self, forKey: .groups) ?? []
        groupMembership = try container.decodeIfPresent([String: String].self, forKey: .groupMembership) ?? [:]
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(accounts, forKey: .accounts)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(groups, forKey: .groups)
        try container.encode(groupMembership, forKey: .groupMembership)
    }

    /// اسم افتراضي غير مكرر لمجموعة جديدة.
    var suggestedGroupName: String {
        var number = groups.count + 1
        let names = Set(groups.map(\.name))
        var name = "المجموعة \(number)"
        while names.contains(name) {
            number += 1
            name = "المجموعة \(number)"
        }
        return name
    }

    /// يضمن أن كل حساب ينتمي لمجموعة واحدة، وألا تتجاوز المجموعة
    /// ٧ حسابات، وأن ترتيب الحسابات يطابق ترتيب المجموعات.
    /// تُستخدم عند التحميل لترحيل البيانات القديمة، وبعد أي تغيير هيكلي.
    mutating func normalizeGroups() {
        let validAccountIDs = Set(accounts.map(\.id))
        groupMembership = groupMembership.filter { validAccountIDs.contains($0.key) }

        var seenGroupIDs = Set<String>()
        groups = groups.filter { group in
            guard !group.id.isEmpty, !seenGroupIDs.contains(group.id) else { return false }
            seenGroupIDs.insert(group.id)
            return true
        }

        // ترحيل المساحات القديمة: تقسيم الحسابات إلى مجموعات من ٧.
        if groups.isEmpty {
            let starts = Array(stride(from: 0, to: accounts.count, by: AccountGroup.capacity))
            if starts.isEmpty {
                groups = [AccountGroup(name: "المجموعة 1")]
            } else {
                for (index, start) in starts.enumerated() {
                    let group = AccountGroup(name: "المجموعة \(index + 1)")
                    groups.append(group)
                    let end = min(start + AccountGroup.capacity, accounts.count)
                    for account in accounts[start..<end] {
                        groupMembership[account.id] = group.id
                    }
                }
            }
        }

        let validGroupIDs = Set(groups.map(\.id))
        groupMembership = groupMembership.filter { validGroupIDs.contains($0.value) }

        var membersByGroup: [String: [Account]] = [:]
        var unassigned: [Account] = []

        for account in accounts {
            if let groupID = groupMembership[account.id],
               (membersByGroup[groupID]?.count ?? 0) < AccountGroup.capacity {
                membersByGroup[groupID, default: []].append(account)
            } else {
                unassigned.append(account)
            }
        }

        // الحسابات بلا مجموعة (أو التي تجاوزت السعة) تُوزّع على آخر
        // مجموعة لديها مكان، وإلا تُنشأ مجموعة جديدة في النهاية.
        for account in unassigned {
            if let group = groups.last(where: { (membersByGroup[$0.id]?.count ?? 0) < AccountGroup.capacity }) {
                groupMembership[account.id] = group.id
                membersByGroup[group.id, default: []].append(account)
            } else {
                let group = AccountGroup(name: suggestedGroupName)
                groups.append(group)
                groupMembership[account.id] = group.id
                membersByGroup[group.id] = [account]
            }
        }

        var ordered: [Account] = []
        var included = Set<String>()
        for group in groups {
            for account in membersByGroup[group.id] ?? [] where !included.contains(account.id) {
                ordered.append(account)
                included.insert(account.id)
            }
        }
        for account in accounts where !included.contains(account.id) {
            ordered.append(account)
        }
        accounts = ordered

        groupMembership = [:]
        for group in groups {
            for account in membersByGroup[group.id] ?? [] {
                groupMembership[account.id] = group.id
            }
        }

        if groups.isEmpty {
            groups = [AccountGroup(name: "المجموعة 1")]
        }
    }
}
#endif
