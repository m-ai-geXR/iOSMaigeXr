import SwiftUI

struct ExamplesView: View {
    @ObservedObject var library3DManager: Library3DManager
    let onExampleSelected: (CodeExample) -> Void
    @Environment(\.dismiss) var dismiss

    @State private var searchText = ""
    @State private var selectedCategory: ExampleCategory? = nil
    @State private var selectedDifficulty: ExampleDifficulty? = nil

    var filteredExamples: [CodeExample] {
        let examples = library3DManager.selectedLibrary.examples

        var filtered = examples

        // Filter by search text (title, description, keywords)
        if !searchText.isEmpty {
            filtered = filtered.filter { example in
                example.title.localizedCaseInsensitiveContains(searchText) ||
                example.description.localizedCaseInsensitiveContains(searchText) ||
                example.keywords.contains { $0.localizedCaseInsensitiveContains(searchText) }
            }
        }

        // Filter by category
        if let category = selectedCategory {
            filtered = filtered.filter { $0.category == category }
        }

        // Filter by difficulty
        if let difficulty = selectedDifficulty {
            filtered = filtered.filter { $0.difficulty == difficulty }
        }

        return filtered
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Search bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.gray)
                    TextField("Search examples or keywords...", text: $searchText)
                        .textFieldStyle(.plain)
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.gray)
                        }
                    }
                }
                .padding()
                .background(Color(.systemGray6))

                // Filters
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        // Category filter
                        Menu {
                            Button("All Categories") {
                                selectedCategory = nil
                            }
                            Divider()
                            ForEach(ExampleCategory.allCases, id: \.self) { category in
                                Button(action: {
                                    selectedCategory = category
                                }) {
                                    Label(category.rawValue, systemImage: category.icon)
                                }
                            }
                        } label: {
                            FilterPill(icon: selectedCategory?.icon ?? "square.grid.2x2",
                                       text: selectedCategory?.rawValue ?? "Category",
                                       isActive: selectedCategory != nil)
                        }

                        // Difficulty filter
                        Menu {
                            Button("All Levels") {
                                selectedDifficulty = nil
                            }
                            Divider()
                            ForEach([ExampleDifficulty.beginner, .intermediate, .advanced], id: \.self) { difficulty in
                                Button(difficulty.rawValue) {
                                    selectedDifficulty = difficulty
                                }
                            }
                        } label: {
                            FilterPill(icon: "chart.bar",
                                       text: selectedDifficulty?.rawValue ?? "Difficulty",
                                       isActive: selectedDifficulty != nil)
                        }

                        // Clear filters
                        if selectedCategory != nil || selectedDifficulty != nil {
                            Button(action: {
                                selectedCategory = nil
                                selectedDifficulty = nil
                            }) {
                                Text("Clear")
                                    .font(.footnote.weight(.medium))
                                    .foregroundColor(.brandAccentText)
                                    .frame(height: Metrics.pillHeight)
                                    .padding(.horizontal, 6)
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }
                .background(Color(.systemGray6))

                // Results count
                HStack {
                    Text("\(filteredExamples.count) example\(filteredExamples.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(library3DManager.selectedLibrary.displayName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)
                .padding(.vertical, 4)

                // Examples list
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(filteredExamples) { example in
                            ExampleCard(example: example) {
                                onExampleSelected(example)
                                dismiss()
                            }
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Examples")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct ExampleCard: View {
    let example: CodeExample
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 8) {
                // Header
                HStack {
                    Text(example.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.primary)
                    Spacer()
                    difficultyBadge
                }

                // Description
                Text(example.description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(2)

                // Keywords (if present)
                if !example.keywords.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(example.keywords.prefix(5), id: \.self) { keyword in
                                Text(keyword)
                                    .font(.caption2.weight(.medium))
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(Capsule().fill(Color.brandAccent.opacity(0.10)))
                                    .foregroundColor(.brandAccentText)
                            }
                            if example.keywords.count > 5 {
                                Text("+\(example.keywords.count - 5)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }

                // Footer
                HStack {
                    Label(example.category.rawValue, systemImage: example.category.icon)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Spacer()

                    if example.aiPromptHints != nil {
                        Image(systemName: "sparkles")
                            .font(.caption)
                            .foregroundColor(.brandAccentText)
                            .accessibilityLabel("Has AI prompt hints")
                    }

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous)
                    .stroke(Color.brandDivider, lineWidth: Metrics.hairline)
            )
        }
        .buttonStyle(.plain)
    }

    var difficultyBadge: some View {
        // Brand status colours: they hold contrast in both appearances.
        let color: Color = {
            switch example.difficulty {
            case .beginner: return .brandSuccess
            case .intermediate: return .brandWarning
            case .advanced: return .brandError
            }
        }()

        return Text(example.difficulty.rawValue)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.12)))
            .foregroundColor(color)
    }
}

// Preview
struct ExamplesView_Previews: PreviewProvider {
    static var previews: some View {
        ExamplesView(
            library3DManager: Library3DManager(),
            onExampleSelected: { _ in }
        )
    }
}

/// Compact filter menu label; filled with the accent when a filter is set.
private struct FilterPill: View {
    let icon: String
    let text: String
    let isActive: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.caption.weight(.semibold))
            Text(text).font(.footnote.weight(.medium)).lineLimit(1)
            Image(systemName: "chevron.down").font(.caption2.weight(.semibold)).opacity(0.7)
        }
        .foregroundColor(isActive ? .white : .brandAccentText)
        .padding(.horizontal, 10)
        .frame(height: Metrics.pillHeight)
        .background(Capsule().fill(isActive ? Color.brandAccent : Color.brandAccent.opacity(0.10)))
        .contentShape(Capsule())
    }
}
