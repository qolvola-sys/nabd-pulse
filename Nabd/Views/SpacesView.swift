import SwiftUI
import UIKit

#if MUTABAA
// MARK: - الشريط العلوي للمساحات

/// شريط علوي شبيه بالشريط السفلي: كل زر يمثّل مساحة مستقلة
/// لها حساباتها وإحصاءاتها وترتيبها اليدوي.
struct SpacesBar: View {
    @EnvironmentObject private var store: AppStore
    @Namespace private var namespace

    @State private var showManager = false
    @State private var showNewSpace = false
    @State private var showFacebook = false
    @State private var newSpaceName = ""

    private var facebookCount: Int {
        store.accounts.filter { $0.platform == .facebook }.count
    }

    var body: some View {
        HStack(spacing: 8) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        ForEach(store.spaces) { space in
                            spaceChip(space)
                                .id(space.id)
                        }
                    }
                    .padding(.horizontal, 1)
                }
                .onChange(of: store.activeSpaceID) { value in
                    withAnimation(.easeInOut(duration: 0.28)) {
                        proxy.scrollTo(value, anchor: .center)
                    }
                }
            }

            Button {
                store.haptic(.selection)
                showFacebook = true
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "globe")
                        .font(.system(size: 11, weight: .bold))
                    Text("فيسبوك")
                        .font(.system(size: 11.5, weight: .bold))
                    if facebookCount > 0 {
                        Text(Num.full(Int64(facebookCount)))
                            .font(.system(size: 8.5, weight: .bold, design: .rounded))
                            .foregroundColor(Theme.cyan)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Theme.cyan.opacity(0.14)))
                    }
                }
                .foregroundColor(Theme.cyan)
                .padding(.horizontal, 9)
                .frame(height: 38)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Theme.cyan.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Theme.cyan.opacity(0.24), lineWidth: 1)
                )
            }
            .buttonStyle(PressableStyle(scale: 0.97))
            .accessibilityIdentifier("open-facebook")

            Menu {
                Button {
                    newSpaceName = ""
                    showNewSpace = true
                } label: {
                    Label("مساحة جديدة", systemImage: "plus.circle")
                }
                Button {
                    showManager = true
                } label: {
                    Label("إدارة المساحات", systemImage: "slider.horizontal.3")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Theme.textSecondary)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(Theme.surface))
                    .overlay(Circle().strokeBorder(Theme.border, lineWidth: 1))
            }
            .buttonStyle(PressableStyle())
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Theme.surfaceRaised.opacity(0.96))
                .shadow(color: .black.opacity(0.45), radius: 18, y: 6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Theme.border.opacity(0.8), lineWidth: 1)
        )
        .padding(.horizontal, 18)
        .padding(.top, 6)
        .padding(.bottom, 6)
        .background(
            LinearGradient(
                stops: [
                    .init(color: Theme.bg, location: 0),
                    .init(color: Theme.bg.opacity(0.92), location: 0.66),
                    .init(color: Theme.bg.opacity(0), location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .top)
        )
        .sheet(isPresented: $showManager) {
            SpacesManagerView()
                .environmentObject(store)
        }
        .fullScreenCover(isPresented: $showFacebook) {
            ZStack {
                AppBackground()
                AccountsView(platform: .facebook)
                    .environmentObject(store)
            }
        }
        .alert("مساحة جديدة", isPresented: $showNewSpace) {
            TextField("اسم المساحة", text: $newSpaceName)
            Button("إضافة") {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                    _ = store.createSpace(named: newSpaceName)
                }
            }
            Button("إلغاء", role: .cancel) {}
        } message: {
            Text("لكل مساحة حساباتها وإحصاءاتها وترتيبها المستقل.")
        }
    }

    private func spaceChip(_ space: AccountSpace) -> some View {
        let active = space.id == store.activeSpaceID
        let accent = Theme.chartPalette[spaceIndex(space) % Theme.chartPalette.count]

        return Button {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
                store.selectSpace(space.id)
            }
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(accent)
                    .frame(width: 6, height: 6)
                    .shadow(color: accent.opacity(0.8), radius: 4)

                Text(space.name)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundColor(active ? Theme.text : Theme.textSecondary)
                    .lineLimit(1)

                Text(Num.full(Int64(space.accounts.count)))
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundColor(active ? Theme.cyan : Theme.textTertiary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(
                        Capsule().fill(active ? Theme.cyan.opacity(0.14) : Theme.bgSoft)
                    )
            }
            .padding(.horizontal, 10)
            .frame(height: 38)
            .background {
                if active {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Theme.cyan.opacity(0.10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(Theme.cyan.opacity(0.24), lineWidth: 1)
                        )
                        .matchedGeometryEffect(id: "space-pill", in: namespace)
                } else {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.clear)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func spaceIndex(_ space: AccountSpace) -> Int {
        store.spaces.firstIndex(where: { $0.id == space.id }) ?? 0
    }
}

// MARK: - إدارة المساحات

struct SpacesManagerView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var showNewSpace = false
    @State private var newSpaceName = ""
    @State private var renameTarget: AccountSpace?
    @State private var renameText = ""
    @State private var deleteTarget: AccountSpace?

    var body: some View {
        ZStack {
            AppBackground()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    header
                    infoCard
                    spacesCard
                    addButton
                    Color.clear.frame(height: 24)
                }
                .padding(.horizontal, 18)
                .padding(.top, 16)
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .alert("مساحة جديدة", isPresented: $showNewSpace) {
            TextField("اسم المساحة", text: $newSpaceName)
            Button("إضافة") {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                    _ = store.createSpace(named: newSpaceName)
                }
            }
            Button("إلغاء", role: .cancel) {}
        } message: {
            Text("ستنتقل مباشرة إلى المساحة الجديدة لتضيف حساباتها.")
        }
        .confirmationDialog(
            "حذف مساحة «\(deleteTarget?.name ?? "")»؟",
            isPresented: Binding(
                get: { deleteTarget != nil },
                set: { if !$0 { deleteTarget = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("حذف المساحة وحساباتها", role: .destructive) {
                if let target = deleteTarget {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                        store.deleteSpace(target.id)
                    }
                }
                deleteTarget = nil
            }
            Button("إلغاء", role: .cancel) { deleteTarget = nil }
        } message: {
            Text("ستُحذف حسابات هذه المساحة من التطبيق فقط، ولن تتأثر الحسابات الأصلية على TikTok أو فيسبوك. لا يمكن التراجع.")
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text("المساحات")
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundColor(Theme.text)
                Text("كل مساحة تجمع حساباتها وإحصاءاتها بشكل مستقل")
                    .font(.system(size: 11.5))
                    .foregroundColor(Theme.textSecondary)
            }
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(Theme.textSecondary)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Theme.surfaceRaised))
            }
            .buttonStyle(PressableStyle())
        }
        .padding(.top, 8)
    }

    private var infoCard: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "square.stack.3d.up.fill")
                .font(.system(size: 13))
                .foregroundColor(Theme.cyan)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Theme.cyan.opacity(0.12)))

            VStack(alignment: .leading, spacing: 4) {
                Text("المساحة النشطة: \(store.activeSpaceName)")
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundColor(Theme.text)
                Text("أضف الحسابات من تبويب الحسابات، وستُحفظ داخل المساحة المختارة. ترتيب الحسابات وكل ٣ حسابات يظهران كما ضبطتهما.")
                    .font(.system(size: 10.5))
                    .foregroundColor(Theme.textSecondary)
                    .lineSpacing(3)
            }
            Spacer(minLength: 0)
        }
        .padding(13)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.cyan.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.cyan.opacity(0.18), lineWidth: 1))
    }

    private var spacesCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(store.spaces.enumerated()), id: \.element.id) { index, space in
                spaceRow(space, index: index)
                if index < store.spaces.count - 1 {
                    HairlineDivider()
                }
            }
        }
        .card(padding: 8)
        .alert(
            "إعادة تسمية المساحة",
            isPresented: Binding(
                get: { renameTarget != nil },
                set: { if !$0 { renameTarget = nil } }
            )
        ) {
            TextField("اسم المساحة", text: $renameText)
            Button("حفظ") {
                if let target = renameTarget {
                    store.renameSpace(target.id, to: renameText)
                }
                renameTarget = nil
            }
            Button("إلغاء", role: .cancel) { renameTarget = nil }
        } message: {
            Text("سيظهر الاسم الجديد في الشريط العلوي.")
        }
    }

    private func spaceRow(_ space: AccountSpace, index: Int) -> some View {
        let active = space.id == store.activeSpaceID
        let accent = Theme.chartPalette[index % Theme.chartPalette.count]

        return HStack(spacing: 8) {
            Button {
                withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
                    store.selectSpace(space.id)
                }
            } label: {
                HStack(spacing: 11) {
                    ZStack {
                        Circle().fill(accent.opacity(0.16))
                        Text(space.name.isEmpty ? "م" : String(space.name.prefix(1)))
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundColor(accent)
                    }
                    .frame(width: 38, height: 38)

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(space.name)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(Theme.text)
                                .lineLimit(1)
                            if active {
                                Chip(text: "الحالية", color: Theme.cyan)
                            }
                        }
                        Text("\(Num.full(Int64(space.accounts.count))) حساب")
                            .font(.system(size: 10))
                            .foregroundColor(Theme.textTertiary)
                    }

                    Spacer(minLength: 4)

                    Image(systemName: active ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 16))
                        .foregroundColor(active ? Theme.cyan : Theme.textTertiary.opacity(0.4))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 9)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Menu {
                Button {
                    renameText = space.name
                    renameTarget = space
                } label: {
                    Label("إعادة تسمية", systemImage: "pencil")
                }

                if index > 0 {
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            store.moveSpace(space.id, by: -1)
                        }
                    } label: {
                        Label("تقديم المساحة", systemImage: "chevron.right")
                    }
                }
                if index < store.spaces.count - 1 {
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            store.moveSpace(space.id, by: 1)
                        }
                    } label: {
                        Label("تأخير المساحة", systemImage: "chevron.left")
                    }
                }

                if store.spaces.count > 1 {
                    Divider()
                    Button(role: .destructive) {
                        deleteTarget = space
                    } label: {
                        Label("حذف المساحة", systemImage: "trash")
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(Theme.textTertiary)
                    .frame(width: 34, height: 38)
            }
        }
    }

    private var addButton: some View {
        Button {
            newSpaceName = ""
            showNewSpace = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 14, weight: .bold))
                Text("إضافة مساحة جديدة")
            }
        }
        .buttonStyle(GhostButtonStyle(height: 48))
    }
}
#endif
