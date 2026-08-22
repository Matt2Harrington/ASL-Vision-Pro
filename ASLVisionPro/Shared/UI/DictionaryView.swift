import SwiftUI

/// Sign reference. No recognition involved, so it works on every platform today and doubles
/// as the tutor's content layer.
///
/// Signs are described by their **phonological parameters** (handshape / location / movement
/// / orientation / non-manual) rather than shown only as a clip. That's what a learner needs
/// to correct their own signing, and it's the same vocabulary the tutor's feedback speaks.
struct DictionaryView: View {
    @State private var catalog = SignCatalog.shared
    @State private var query = ""
    @State private var selectedCategory: SignEntry.Category?
    @State private var selected: SignEntry?
    @FocusState private var searchFocused: Bool

    private var results: [SignEntry] {
        let base = selectedCategory.map { catalog.entries(in: $0) } ?? catalog.entries
        guard !query.isEmpty else { return base.sorted { $0.gloss < $1.gloss } }
        let q = query.lowercased()
        return base
            .filter { $0.gloss.lowercased().contains(q) || $0.meaning.lowercased().contains(q) }
            .sorted { $0.gloss < $1.gloss }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                    searchField

                    if query.isEmpty {
                        categoryFilter
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        SectionHeader(title: selectedCategory?.title ?? "All signs",
                                      trailing: "\(results.count)")
                        if results.isEmpty {
                            emptyState
                        } else {
                            signGrid
                        }
                    }
                }
                .padding(28)
            }
            .dismissesKeyboardOnScroll()
            .navigationTitle("Dictionary")
            .navigationDestination(item: $selected) { SignDetailView(entry: $0) }
        }
    }

    // MARK: - Search

    private var searchField: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search signs", text: $query)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .focused($searchFocused)
                .submitLabel(.search)
                .onSubmit { searchFocused = false }
            if !query.isEmpty {
                Button { query = ""; searchFocused = false } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(.regularMaterial, in: Capsule())
    }

    // MARK: - Categories

    private var categoryFilter: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Browse by category")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    chip(title: "All", count: catalog.entries.count, isSelected: selectedCategory == nil) {
                        selectedCategory = nil
                    }
                    ForEach(SignEntry.Category.allCases, id: \.self) { category in
                        let count = catalog.entries(in: category).count
                        if count > 0 {
                            chip(title: category.title, count: count,
                                 isSelected: selectedCategory == category) {
                                selectedCategory = selectedCategory == category ? nil : category
                            }
                        }
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
            }
        }
    }

    private func chip(title: String, count: Int, isSelected: Bool,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title).font(.callout.weight(.medium))
                Text("\(count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .background(isSelected ? AnyShapeStyle(Theme.Accent.dictionary.opacity(0.35))
                               : AnyShapeStyle(.regularMaterial),
                    in: Capsule())
        .hoverEffect()
    }

    // MARK: - Results

    private var signGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: Theme.itemSpacing)],
                  spacing: Theme.itemSpacing) {
            ForEach(results) { entry in
                CardButton { selected = entry } content: {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 12) {
                            IconBadge(symbol: entry.isTwoHanded ? "hands.sparkles.fill" : "hand.raised.fill",
                                      tint: Theme.Accent.dictionary, size: 38)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(entry.gloss).font(.headline)
                                Text(entry.meaning)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        Text(entry.handshape + " · " + entry.location)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        CardSurface {
            VStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 32))
                    .foregroundStyle(.secondary)
                Text("No signs match “\(query)”")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        }
    }
}

/// Detail for one sign — the parameter breakdown is the substance.
struct SignDetailView: View {
    let entry: SignEntry

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header

                VStack(alignment: .leading, spacing: 16) {
                    SectionHeader(title: "How it's formed")
                    CardSurface {
                        VStack(alignment: .leading, spacing: 18) {
                            parameter("Handshape", entry.handshape, "hand.raised.fill", .blue)
                            parameter("Location", entry.location, "mappin.circle.fill", .green)
                            parameter("Movement", entry.movement, "arrow.triangle.turn.up.right.diamond.fill", .orange)
                            parameter("Orientation", entry.orientation, "rotate.3d", .purple)
                            if let nm = entry.nonManual {
                                parameter("Non-manual", nm, "face.smiling.fill", .pink)
                            }
                        }
                    }
                }

                if entry.nonManual != nil {
                    Label("Non-manual markers carry grammar in ASL — facial expression and head movement can change meaning, not just tone.",
                          systemImage: "info.circle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(entry.gloss)
    }

    private var header: some View {
        HStack(spacing: 18) {
            IconBadge(symbol: entry.isTwoHanded ? "hands.sparkles.fill" : "hand.raised.fill",
                      tint: Theme.Accent.dictionary, size: 62)
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.gloss)
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                Text(entry.meaning)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Text(entry.isTwoHanded ? "Two-handed" : "One-handed")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func parameter(_ title: String, _ value: String,
                           _ symbol: String, _ tint: Color) -> some View {
        HStack(alignment: .top, spacing: 14) {
            IconBadge(symbol: symbol, tint: tint, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Text(value).font(.body)
            }
            Spacer(minLength: 0)
        }
    }
}
