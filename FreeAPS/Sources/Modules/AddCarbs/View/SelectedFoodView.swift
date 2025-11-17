import SwiftUI

struct SelectedFoodView: View {
    let food: AIFoodItem
    let foodImage: UIImage?
    @Binding var portionGrams: Double
    var onChange: () -> Void
    var onTakeOver: (AIFoodItem) -> Void

    @State private var showMultiplierEditor = false

    private var isAIProduct: Bool {
        (food.brand ?? "").lowercased().contains("ai overall analysis")
    }

    private var displayCarbs: Double {
        isAIProduct ? food.carbs : food.carbs * (portionGrams / 100.0)
    }

    private var displayFat: Double {
        isAIProduct ? food.fat : food.fat * (portionGrams / 100.0)
    }

    private var displayProtein: Double {
        isAIProduct ? food.protein : food.protein * (portionGrams / 100.0)
    }

    private var displayCalories: Double {
        isAIProduct ? food.calories : food.calories * (portionGrams / 100.0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Group {
                    if let foodImage = foodImage {
                        Image(uiImage: foodImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 75, height: 75)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                            )
                    } else if let imageURLString = food.imageURL,
                              let imageURL = URL(string: imageURLString)
                    {
                        AsyncImage(url: imageURL) { phase in
                            switch phase {
                            case .empty:
                                ProgressView()
                                    .frame(width: 75, height: 75)
                            case let .success(image):
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 75, height: 75)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                            case .failure:
                                placeholderImage
                            @unknown default:
                                placeholderImage
                            }
                        }
                    } else {
                        placeholderImage
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(food.name)
                        .font(.headline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 4) {
                        Image(systemName: isAIAnalysisProduct(food) ? "brain" : "scalemass")
                            .font(.caption)

                        if isAIAnalysisProduct(food) {
                            Text("AI Analysis")
                                .font(.caption)
                        } else if portionGrams == 100.0 {
                            Text("100g")
                                .font(.caption)
                        }
                    }
                    .fontWeight(.semibold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        isAIAnalysisProduct(food) ? Color.purple.opacity(0.2) :
                            (portionGrams == 100.0 ? Color.blue.opacity(0.2) : Color.clear)
                    )
                    .foregroundColor(
                        isAIAnalysisProduct(food) ? .purple :
                            (portionGrams == 100.0 ? .blue : .clear)
                    )
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(
                                isAIAnalysisProduct(food) ? Color.purple.opacity(0.3) :
                                    (portionGrams == 100.0 ? Color.blue.opacity(0.3) : Color.clear),
                                lineWidth: 1
                            )
                    )
                }
            }

            if !isAIAnalysisProduct(food) {
                HStack {
                    Text("Amount:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Button {
                        showMultiplierEditor = true
                    } label: {
                        HStack(spacing: 4) {
                            Text("\(portionGrams, specifier: "%.0f")g")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            Image(systemName: "pencil")
                                .font(.system(size: 14, weight: .bold))
                        }
                        .foregroundColor(.blue)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(6)
                    }
                    .buttonStyle(PlainButtonStyle())

                    Spacer()
                }
            }

            HStack(spacing: 8) {
                NutritionBadge(
                    value: displayCarbs,
                    unit: "g",
                    label: "Carbs",
                    color: .orange,
                    // icon: "c.square"
                )
                NutritionBadge(
                    value: displayFat,
                    unit: "g",
                    label: "Fett",
                    color: .blue,
                    // icon: "f.square"
                )
                NutritionBadge(
                    value: displayProtein,
                    unit: "g",
                    label: "Protein",
                    color: .green,
                    // icon: "p.square"
                )
                if food.calories > 0 {
                    NutritionBadge(
                        value: displayCalories,
                        unit: "kcal",
                        label: "Cal",
                        color: .red,
                        // icon: "flame"
                    )
                }
            }

            HStack(spacing: 12) {
                Button(action: onChange) {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                        Text("Food")
                    }
                    .font(.subheadline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 2)
                }
                .buttonStyle(.bordered)
                .tint(.blue)

                Button {
                    let adjustedFood = AIFoodItem(
                        name: food.name,
                        brand: food.brand,
                        calories: displayCalories,
                        carbs: displayCarbs,
                        protein: displayProtein,
                        fat: displayFat,
                        imageURL: food.imageURL
                    )
                    onTakeOver(adjustedFood)
                } label: {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Take Over")
                    }
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 2)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        // .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
        .sheet(isPresented: $showMultiplierEditor) {
            MultiplierEditorView(grams: $portionGrams)
        }
    }

    private var placeholderImage: some View {
        Image(systemName: "photo")
            .frame(width: 60, height: 60)
            .background(Color.gray.opacity(0.2))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .foregroundColor(.secondary)
    }

    private struct NutritionBadge: View {
        let value: Double
        let unit: String
        let label: String
        let color: Color
        let icon: String

        init(value: Double, unit: String, label: String, color: Color, icon: String? = nil) {
            self.value = value
            self.unit = unit
            self.label = label
            self.color = color
            self.icon = icon ?? ""
        }

        var body: some View {
            HStack(spacing: 4) {
                if !icon.isEmpty {
                    Image(systemName: icon)
                        .font(.system(size: 10))
                }
                VStack(spacing: 2) {
                    Text("\(value, specifier: "%.1f")\(NSLocalizedString(unit, comment: ""))")
                        .font(.system(size: 12, weight: .bold))
                    Text(NSLocalizedString(label, comment: ""))
                        .font(.system(size: 10, weight: .medium))
                }
            }
            .foregroundColor(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(color.opacity(0.15))
            .cornerRadius(8)
        }
    }
}
