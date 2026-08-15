import SwiftUI

/// Direction 3 — the sign reference. No recognition involved, so this works on every
/// platform today and doubles as the tutor's content layer.
///
/// Signs are described by their **phonological parameters** (handshape / location / movement
/// / orientation / non-manual) rather than shown only as a clip. That is what a learner
/// actually needs to correct their own signing, and it's the same vocabulary the tutor's
/// feedback speaks.
struct DictionaryView: View {
    @State private var catalog = SignCatalog.shared
    @State private var query = ""
    @State private var selectedCategory: SignEntry.Category?

    private var results: [SignEntry] {
        let base = selectedCategory.map { catalog.entries(in: $0) } ?? catalog.search(query)
        guard !query.isEmpty else { return base }
        let q = query.lowercased()
        return base.filter { $0.gloss.lowercased().contains(q) || $0.meaning.lowercased().contains(q) }
    }

    var body: some View {
        NavigationStack {
            List {
                if selectedCategory == nil && query.isEmpty {
                    categorySection
                }
                Section(selectedCategory?.title ?? "All Signs") {
                    ForEach(results) { entry in
                        NavigationLink(value: entry) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.gloss).font(.headline)
                                Text(entry.meaning)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Sign Dictionary")
            .navigationDestination(for: SignEntry.self) { SignDetailView(entry: $0) }
            .searchable(text: $query, prompt: "Search signs")
            .toolbar {
                if selectedCategory != nil {
                    Button("All") { selectedCategory = nil }
                }
            }
        }
    }

    private var categorySection: some View {
        Section("Categories") {
            ForEach(SignEntry.Category.allCases, id: \.self) { category in
                let count = catalog.entries(in: category).count
                if count > 0 {
                    Button { selectedCategory = category } label: {
                        HStack {
                            Text(category.title)
                            Spacer()
                            Text("\(count)").foregroundStyle(.secondary)
                            Image(systemName: "chevron.right")
                                .font(.caption).foregroundStyle(.tertiary)
                        }
                        // Without an explicit hit shape, a .plain button inside a List row
                        // only responds on its opaque label content — taps on the row's
                        // empty space are swallowed. Verified on device: the row did nothing.
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

/// Detail for one sign — the parameter breakdown is the substance here.
struct SignDetailView: View {
    let entry: SignEntry

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(entry.gloss)
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                    Text(entry.meaning)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    Label(entry.isTwoHanded ? "Two-handed" : "One-handed",
                          systemImage: entry.isTwoHanded ? "hands.sparkles" : "hand.raised")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                VStack(alignment: .leading, spacing: 14) {
                    Text("Parameters").font(.headline)
                    parameter("Handshape", entry.handshape, "hand.raised.fill")
                    parameter("Location", entry.location, "mappin.circle.fill")
                    parameter("Movement", entry.movement, "arrow.triangle.turn.up.right.diamond.fill")
                    parameter("Orientation", entry.orientation, "rotate.3d")
                    if let nm = entry.nonManual {
                        parameter("Non-manual", nm, "face.smiling.fill")
                    }
                }
                .padding(20)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))

                if entry.nonManual != nil {
                    Text("Non-manual markers carry grammar in ASL — facial expression and head movement can change meaning, not just tone.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(entry.gloss)
    }

    private func parameter(_ title: String, _ value: String, _ symbol: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(.tint)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(value).font(.body)
            }
        }
    }
}
