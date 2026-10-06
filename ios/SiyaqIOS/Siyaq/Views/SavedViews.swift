import SwiftUI

/// المحفوظات: قراءة من الجهاز دون اتصال، فتح، وحذف.
struct SavedListView: View {
    @Environment(SavedResultsStore.self) private var store

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // حالة دائمة لا تختفي بإغلاق التنبيه: لا نُخفي فشلًا قائمًا.
                if let reason = store.readOnlyReason {
                    NoticeCard(.warning, title: "المحفوظات للقراءة فقط", message: reason)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                }
                Group {
                    if store.entries.isEmpty {
                        emptyState
                    } else {
                        list
                    }
                }
            }
            .background(Palette.ground.ignoresSafeArea())
            .navigationTitle("المحفوظات")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(Palette.ground, for: .navigationBar)
            .toolbar {
                if !store.entries.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        EditButton()
                    }
                }
            }
            .navigationDestination(for: UUID.self) { id in
                if let entry = store.entry(id: id) {
                    SavedDetailView(entry: entry)
                } else {
                    Text("حُذفت هذه النتيجة من المحفوظات.")
                        .siyaqFont(.body)
                        .foregroundStyle(Palette.muted)
                }
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("لا توجد محفوظات بعد", systemImage: "bookmark")
        } description: {
            Text("احفظ نتيجة من شاشة المراجعة لتعود إليها هنا، حتى دون اتصال.")
        }
        .foregroundStyle(Palette.navy)
    }

    private var list: some View {
        List {
            Section {
                ForEach(store.entries) { entry in
                    NavigationLink(value: entry.id) {
                        SavedRow(entry: entry)
                    }
                    .listRowBackground(Color.white)
                }
                .onDelete { offsets in
                    _ = store.delete(atOffsets: offsets)
                }
            } footer: {
                Text("تُقرأ المحفوظات من جهازك دون اتصال. المراجعة الجديدة تحتاج اتصالًا بالخدمة.")
                    .siyaqFont(.small)
                    .foregroundStyle(Palette.muted)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }
}

struct SavedRow: View {
    let entry: SavedEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            AdaptiveRow(spacing: 6) {
                Text(entry.candidate.map { ArabicFormat.location(of: $0.verses) } ?? "نتيجة")
                    .siyaqFont(.bodyBold)
                    .foregroundStyle(Palette.navy)
                if entry.origin == .preview {
                    Text("معاينة")
                        .siyaqFont(.small)
                        .foregroundStyle(Palette.navy)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Tone.lavender.background))
                }
                if entry.candidate?.kind == .possible {
                    Text("تشابه محتمل")
                        .siyaqFont(.small)
                        .foregroundStyle(Palette.navy)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Tone.coral.background))
                }
            }
            Text(entry.result.quote)
                .siyaqFont(.caption)
                .foregroundStyle(Palette.muted)
                .lineLimit(2)
            Text(ArabicFormat.date(entry.savedAt) + (entry.sourceVersion.isEmpty ? "" : " · إصدار \(entry.sourceVersion)"))
                .siyaqFont(.small)
                .foregroundStyle(Palette.muted)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

struct SavedDetailView: View {
    let entry: SavedEntry

    @Environment(SavedResultsStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false

    var body: some View {
        ScrollView {
            Group {
                if let candidate = entry.candidate {
                    ResultDetailView(result: entry.result, candidate: candidate, origin: entry.origin, savedAt: entry.savedAt)
                } else {
                    NoticeCard(.info, message: "هذه النتيجة لا تحتوي موضعًا محددًا.")
                }
            }
            .padding(.horizontal, 23)
            .padding(.top, 12)
            .padding(.bottom, 32)
        }
        .background(Palette.ground.ignoresSafeArea())
        .navigationTitle("نتيجة محفوظة")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Palette.ground, for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if let candidate = entry.candidate {
                    ShareLink(
                        item: ShareText.make(result: entry.result, candidate: candidate),
                        subject: Text("سِياق"),
                        preview: SharePreview(ArabicFormat.location(of: candidate.verses))
                    ) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("مشاركة النص والموضع والمصدر")
                }
                Button(role: .destructive) {
                    confirmDelete = true
                } label: {
                    Image(systemName: "trash")
                }
                .accessibilityLabel("حذف من المحفوظات")
            }
        }
        .confirmationDialog("حذف هذه النتيجة من المحفوظات؟", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("حذف", role: .destructive) {
                if store.delete(id: entry.id) { dismiss() }
            }
            Button("إلغاء", role: .cancel) {}
        }
    }
}
