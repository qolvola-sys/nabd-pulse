import SwiftUI

#if MUTABAA
/// نافذة صغيرة لإنشاء مجموعة أو إعادة تسميتها.
struct GroupEditorSheet: View {
    enum Mode {
        /// إنشاء مجموعة جديدة مع اسم مقترح.
        case create(suggestedName: String, groupCount: Int)
        /// إعادة تسمية مجموعة موجودة.
        case rename(currentName: String, memberCount: Int)
    }

    let mode: Mode
    /// يعيد `true` عند نجاح الحفظ لتُغلق النافذة.
    let onSave: (String) -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @FocusState private var isFocused: Bool

    init(mode: Mode, onSave: @escaping (String) -> Bool) {
        self.mode = mode
        self.onSave = onSave
        switch mode {
        case .create(let suggestedName, _):
            _name = State(initialValue: suggestedName)
        case .rename(let currentName, _):
            _name = State(initialValue: currentName)
        }
    }

    private var title: String {
        switch mode {
        case .create: return "مجموعة جديدة"
        case .rename: return "إعادة تسمية المجموعة"
        }
    }

    private var subtitle: String {
        switch mode {
        case .create(_, let groupCount):
            if groupCount == 0 {
                return "أول مجموعة في هذه المساحة"
            }
            return "المجموعة رقم \(Num.full(Int64(groupCount + 1))) في هذه المساحة"
        case .rename(_, let memberCount):
            return "\(Num.full(Int64(memberCount))) من \(Num.full(Int64(AccountGroup.capacity))) حسابات"
        }
    }

    private var icon: String {
        switch mode {
        case .create: return "square.stack.3d.up.fill"
        case .rename: return "pencil.line"
        }
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        ZStack {
            AppBackground()

            VStack(spacing: 16) {
                HStack(alignment: .center, spacing: 11) {
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(Theme.cyan)
                        .frame(width: 40, height: 40)
                        .background(
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .fill(Theme.cyan.opacity(0.12))
                        )

                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .font(.system(size: 17, weight: .heavy, design: .rounded))
                            .foregroundColor(Theme.text)
                        Text(subtitle)
                            .font(.system(size: 10.5))
                            .foregroundColor(Theme.textTertiary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 4)

                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(Theme.textSecondary)
                            .frame(width: 30, height: 30)
                            .background(Circle().fill(Theme.surfaceRaised))
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityIdentifier("group-name-cancel")
                }

                VStack(alignment: .leading, spacing: 7) {
                    Text("اسم المجموعة")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Theme.textTertiary)

                    TextField("مثال: المتابعة اليومية", text: $name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Theme.text)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .focused($isFocused)
                        .onSubmit(save)
                        .padding(.horizontal, 13)
                        .frame(height: 46)
                        .background(
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .fill(Theme.surfaceRaised)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .strokeBorder(
                                    isFocused ? Theme.cyan.opacity(0.55) : Theme.borderSoft,
                                    lineWidth: 1
                                )
                        )
                        .accessibilityIdentifier("group-name-field")
                }

                HStack(spacing: 7) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 9, weight: .semibold))
                    Text("تتسع المجموعة حتى \(Num.full(Int64(AccountGroup.capacity))) حسابات، ويمكنك تغيير اسمها في أي وقت.")
                        .font(.system(size: 9.5))
                        .lineLimit(2)
                    Spacer(minLength: 0)
                }
                .foregroundColor(Theme.textTertiary)

                HStack(spacing: 9) {
                    Button {
                        dismiss()
                    } label: {
                        Text("إلغاء")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundColor(Theme.textSecondary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 42)
                            .background(
                                RoundedRectangle(cornerRadius: 13, style: .continuous)
                                    .fill(Theme.surfaceRaised)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 13, style: .continuous)
                                    .strokeBorder(Theme.borderSoft, lineWidth: 1)
                            )
                    }
                    .buttonStyle(PressableStyle(scale: 0.99))

                    Button(action: save) {
                        HStack(spacing: 5) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .bold))
                            Text("حفظ")
                                .font(.system(size: 12.5, weight: .bold))
                        }
                        .foregroundColor(Color(hex: 0x061016))
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                        .background(
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .fill(Theme.cyanGradient)
                        )
                        .opacity(trimmedName.isEmpty ? 0.45 : 1)
                    }
                    .buttonStyle(PressableStyle(scale: 0.99))
                    .disabled(trimmedName.isEmpty)
                    .accessibilityIdentifier("group-name-save")
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 14)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                isFocused = true
            }
        }
    }

    private func save() {
        guard !trimmedName.isEmpty else { return }
        if onSave(trimmedName) {
            dismiss()
        }
    }
}
#endif
