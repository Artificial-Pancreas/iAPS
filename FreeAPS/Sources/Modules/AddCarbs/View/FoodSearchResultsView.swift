import LoopKit
import SwiftUI

/// View displaying search results from both OpenFoodFacts and AI food database
struct FoodSearchResultsView: View {
    let searchResults: [OpenFoodFactsProduct]
    let aiSearchResults: [AIFoodItem]
    let isSearching: Bool
    let errorMessage: String?
    let onProductSelected: (OpenFoodFactsProduct) -> Void
    let onAIProductSelected: (AIFoodItem) -> Void

    var body: some View {
        VStack(spacing: 0) {
            if isSearching {
                searchingView
                    .onAppear {
                        print("🔍 FoodSearchResultsView: Showing searching state")
                    }
            } else if let errorMessage = errorMessage {
                errorView(message: errorMessage)
                    .onAppear {
                        print("🔍 FoodSearchResultsView: Showing error state - \(errorMessage)")
                    }
            } else if searchResults.isEmpty, aiSearchResults.isEmpty {
                emptyResultsView
                    .onAppear {
                        print("🔍 FoodSearchResultsView: Showing empty results state")
                    }
            } else {
                resultsListView
                    .onAppear {
                        print(
                            "🔍 FoodSearchResultsView: Showing \(searchResults.count) traditional + \(aiSearchResults.count) AI results"
                        )
                    }
            }
        }
        .onAppear {
            print(
                "🔍 FoodSearchResultsView body: isSearching=\(isSearching), traditionalResults=\(searchResults.count), aiResults=\(aiSearchResults.count), error=\(errorMessage ?? "none")"
            )
        }
    }

    // MARK: - Subviews

    private var searchingView: some View {
        VStack(spacing: 16) {
            ZStack {
                // Outer pulsing ring
                Circle()
                    .stroke(Color.blue.opacity(0.3), lineWidth: 2)
                    .frame(width: 70, height: 70)
                    .scaleEffect(pulseScale)
                    .animation(
                        .easeInOut(duration: 1.2)
                            .repeatForever(autoreverses: true),
                        value: pulseScale
                    )

                // Inner filled circle
                Circle()
                    .fill(Color.blue.opacity(0.15))
                    .frame(width: 60, height: 60)
                    .scaleEffect(secondaryPulseScale)
                    .animation(
                        .easeInOut(duration: 0.8)
                            .repeatForever(autoreverses: true),
                        value: secondaryPulseScale
                    )

                // Rotating magnifying glass
                Image(systemName: "magnifyingglass")
                    .font(.title)
                    .foregroundColor(.blue)
                    .rotationEffect(rotationAngle)
                    .animation(
                        .linear(duration: 2.0)
                            .repeatForever(autoreverses: false),
                        value: rotationAngle
                    )
            }
            .onAppear {
                pulseScale = 1.3
                secondaryPulseScale = 1.1
                rotationAngle = .degrees(360)
            }

            VStack(spacing: 6) {
                HStack(spacing: 4) {
                    Text(NSLocalizedString("Searching foods", comment: "Text shown while searching for foods"))
                        .font(.headline)
                        .foregroundColor(.primary)

                    // Animated dots
                    HStack(spacing: 2) {
                        ForEach(0 ..< 3) { index in
                            Circle()
                                .fill(Color.blue)
                                .frame(width: 4, height: 4)
                                .scaleEffect(dotScales[index])
                                .animation(
                                    .easeInOut(duration: 0.6)
                                        .repeatForever()
                                        .delay(Double(index) * 0.2),
                                    value: dotScales[index]
                                )
                        }
                    }
                    .onAppear {
                        for i in 0 ..< 3 {
                            dotScales[i] = 1.5
                        }
                    }
                }

                Text(NSLocalizedString("Finding the best matches for you", comment: "Subtitle shown while searching for foods"))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    @State private var pulseScale: CGFloat = 1.0
    @State private var secondaryPulseScale: CGFloat = 1.0
    @State private var rotationAngle: Angle = .degrees(0)
    @State private var dotScales: [CGFloat] = [1.0, 1.0, 1.0]

    private func errorView(message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title2)
                .foregroundColor(.orange)

            Text(NSLocalizedString("Search Error", comment: "Title for food search error"))
                .font(.headline)
                .foregroundColor(.primary)

            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var emptyResultsView: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.title)
                .foregroundColor(.orange)

            Text(NSLocalizedString("No Foods Found", comment: "Title when no food search results"))
                .font(.headline)
                .foregroundColor(.primary)

            VStack(spacing: 8) {
                Text(NSLocalizedString(
                    "Check your spelling and try again",
                    comment: "Primary suggestion when no food search results"
                ))
                    .font(.subheadline)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)

                Text(NSLocalizedString(
                    "Try simpler terms like \"bread\" or \"apple\", or scan a barcode",
                    comment: "Secondary suggestion when no food search results"
                ))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            // Helpful suggestions
            VStack(spacing: 4) {
                Text("💡 Search Tips:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fontWeight(.medium)

                VStack(alignment: .leading, spacing: 2) {
                    Text("• Use simple, common food names")
                    Text("• Try brand names (e.g., \"Cheerios\")")
                    Text("• Check spelling carefully")
                    Text("• Use the barcode scanner for packaged foods")
                }
                .font(.caption2)
                .foregroundColor(.secondary)
            }
            .padding(.top, 8)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var resultsListView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                // AI Results Section
                if !aiSearchResults.isEmpty {
                    Section {
                        Text("🤖 AI Search Results")
                            .font(.headline)
                            .foregroundColor(.purple)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal)
                            .padding(.top, 8)

                        ForEach(aiSearchResults, id: \.id) { aiProduct in
                            AIFoodSearchResultRow(
                                product: aiProduct,
                                onSelected: { onAIProductSelected(aiProduct) }
                            )
                            .background(Color(.systemBackground))

                            if aiProduct.id != aiSearchResults.last?.id {
                                Divider()
                                    .padding(.leading, 16)
                            }
                        }
                    }

                    Divider()
                        .padding(.vertical, 8)
                }

                // Traditional Results Section
                if !searchResults.isEmpty {
                    Section {
                        Text("📦 Database Results")
                            .font(.headline)
                            .foregroundColor(.blue)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal)
                            .padding(.top, aiSearchResults.isEmpty ? 0 : 8)

                        ForEach(searchResults, id: \.id) { product in
                            FoodSearchResultRow(
                                product: product,
                                onSelected: { onProductSelected(product) }
                            )
                            .background(Color(.systemBackground))

                            if product.id != searchResults.last?.id {
                                Divider()
                                    .padding(.leading, 16)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - AI Food Search Result Row

private struct AIFoodSearchResultRow: View {
    let product: AIFoodItem
    let onSelected: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.purple.opacity(0.1))
                .frame(width: 50, height: 50)
                .overlay(
                    Image(systemName: "sparkles")
                        .font(.title3)
                        .foregroundColor(.purple)
                )

            // Product details
            VStack(alignment: .leading, spacing: 4) {
                Text(product.name)
                    .font(.headline)
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                if let brand = product.brand, !brand.isEmpty {
                    Text(brand)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                // Nutrition info
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(format: "%.1fg carbs per 100g", product.carbs))
                        .font(.caption)
                        .foregroundColor(.blue)
                        .lineLimit(1)

                    // Additional nutrition
                    HStack(spacing: 8) {
                        Text(String(format: "%.1fg protein", product.protein))
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        Text(String(format: "%.1fg fat", product.fat))
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        Text(String(format: "%.0f kcal", product.calories))
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        Spacer()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                onSelected()
            }

            // Selection indicator
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Food Search Result Row (Original)

private struct FoodSearchResultRow: View {
    let product: OpenFoodFactsProduct
    let onSelected: () -> Void
    var validatedImageURL: URL? {
        guard let urlString = product.imageURL ?? product.imageFrontURL else {
            return nil
        }

        var cleanedURL = urlString
        if cleanedURL.hasPrefix("../") {
            cleanedURL = String(cleanedURL.dropFirst(3))
        }
        if !cleanedURL.hasPrefix("http") {
            cleanedURL = "https://static.openfoodfacts.org\(cleanedURL)"
        }

        return URL(string: cleanedURL)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Group {
                if let imageURL = product.imageFrontURL ?? product.imageURL,
                   let url = URL(string: imageURL)
                {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .empty:
                            ProgressView()
                                .scaleEffect(0.7)
                        case let .success(image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        case let .failure(error):
                            VStack {
                                Image(systemName: "exclamationmark.triangle")
                                    .foregroundColor(.orange)
                                Text("Failed to load, " + error.localizedDescription)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        @unknown default:
                            EmptyView()
                        }
                    }
                    .frame(width: 50, height: 50)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(.systemGray5))
                        .frame(width: 50, height: 50)
                        .overlay(
                            Image(systemName: "takeoutbag.and.cup.and.straw")
                                .font(.title3)
                                .foregroundColor(.secondary)
                        )
                }
            }
            // Product details
            VStack(alignment: .leading, spacing: 4) {
                Text(product.displayName)
                    .font(.headline)
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                if let brands = product.brands, !brands.isEmpty {
                    Text(brands)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                // Essential nutrition info
                VStack(alignment: .leading, spacing: 2) {
                    VStack(alignment: .leading, spacing: 1) {
                        // Carbs per serving or per 100g
                        if let carbsPerServing = product.carbsPerServing {
                            Text(String(format: "%.1fg carbs per %@", carbsPerServing, product.servingSizeDisplay))
                                .font(.caption)
                                .foregroundColor(.blue)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            Text(String(format: "%.1fg carbs per 100g", product.nutriments.carbohydrates))
                                .font(.caption)
                                .foregroundColor(.blue)
                                .lineLimit(1)
                        }
                    }

                    // Additional nutrition if available
                    HStack(spacing: 8) {
                        if let protein = product.nutriments.proteins {
                            Text(String(format: "%.1fg protein", protein))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }

                        if let fat = product.nutriments.fat {
                            Text(String(format: "%.1fg fat", fat))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }

                        Spacer()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                print("🔍 User tapped on food result: \(product.displayName)")
                onSelected()
            }

            // Selection indicator
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct AIFoodItem: Identifiable, Codable, Equatable {
    var id: String {
        "\(name)-\(brand ?? "")-\(calories)-\(carbs)"
    }

    let name: String
    let brand: String?
    let calories: Double
    let carbs: Double
    let protein: Double
    let fat: Double
    let imageURL: String?

    enum CodingKeys: String, CodingKey {
        case name
        case brand
        case calories
        case carbs
        case protein
        case fat
        case imageURL
    }

    static func == (lhs: AIFoodItem, rhs: AIFoodItem) -> Bool {
        lhs.id == rhs.id
    }
}
