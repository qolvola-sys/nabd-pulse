import Foundation

/// هوية النسختين:
/// - `Nabd`  : النسخة الحالية «نبض».
/// - `Mutabaa`: النسخة الثانية «المتابعة» التي تحسب التقييم الأسبوعي من كل منشورات آخر ٧ أيام.
enum AppVariant {
    #if MUTABAA
    static let name = "المتابعة"
    static let mark = "م"
    static let urlScheme = "mutabaa"
    static let readsEveryWeeklyPost = true
    static let weekdaySubtitle = "من 100 — يُحسب من كل منشورات آخر ٧ أيام"
    #else
    static let name = "نبض"
    static let mark = "ن"
    static let urlScheme = "nabd"
    static let readsEveryWeeklyPost = false
    static let weekdaySubtitle = "من 100 — كل ١٠٬٠٠٠ مشاهدة = نقطة، و١٬٠٠٠٬٠٠٠ = 100%"
    #endif

    /// نص بديل عندما لا تكتمل نافذة الأسبوع.
    static var incompleteWeeklyNote: String {
        readsEveryWeeklyPost
            ? "يقرأ «\(name)» كل منشورات آخر ٧ أيام؛ وإذا تعذّر الوصول لبعضها تُحسب النتيجة من المنشورات المحمّلة."
            : "النتيجة من أحدث ١٠ منشورات فقط؛ الحسابات كثيفة النشر تحتاج ربطاً رسمياً لقراءة كل المنشورات."
    }

    /// رقم الإصدار الحقيقي من Info.plist، حتى يتحقق المستخدم من النسخة
    /// المثبّتة بدل الاعتماد على نص ثابت قد يقدم.
    static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? ""
        let build = info?["CFBundleVersion"] as? String ?? ""
        if !short.isEmpty && !build.isEmpty {
            return "\(short) (\(build))"
        }
        return short.isEmpty ? build : short
    }

    static var versionLabel: String {
        version.isEmpty ? "" : "الإصدار \(version)"
    }
}
