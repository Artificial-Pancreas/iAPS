import SwiftUI
import UIKit

struct AIProgressView: View {
    @ObservedObject var state: FoodSearchStateModel

    let onCancel: () -> Void

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.clear
                    .background(.regularMaterial)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    Spacer(minLength: 0)

                    searchTypeView
                        .padding(.horizontal, 20)
                        .frame(
                            maxWidth: .infinity,
                            maxHeight: Swift.max(geometry.size.height - geometry.safeAreaInsets.bottom - 140, 20)
                        )

                    Spacer(minLength: 0)
                }
                .frame(maxHeight: .infinity)
                .padding(.bottom, 140)

                VStack(spacing: 0) {
                    if state.analysisError == nil {
                        HStack {
                            if let model = state.analysisModel {
                                Text(model)
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .fontDesign(.rounded)
                                    .foregroundStyle(.primary.opacity(0.7))
                                    .transition(.scale.combined(with: .opacity))
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 8)
                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: state.analysisModel)

                        AnalyzingPill(
                            title: NSLocalizedString("Analyzing food with AI…", comment: ""),
                            startDate: state.analysisStart,
                            eta: state.analysisEta,
                            endDate: state.analysisEnd,
                            onCancel: {
                                onCancel()
                            }
                        )
                        .padding(.horizontal, 20)
                        .padding(.bottom, max(geometry.safeAreaInsets.bottom, 120))
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: state.analysisError)
            }
        }
        .ignoresSafeArea()
    }

    private var searchTypeView: some View {
        let isAnalysisComplete = state.analysisEnd != nil

        return VStack(spacing: 12) {
            switch state.aiAnalysisRequest {
            case let .image(image, _):
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()

            case let .query(query):
                HStack(alignment: .top, spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.cyan.opacity(0.2),
                                        Color.blue.opacity(0.15)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 44, height: 44)

                        Image(systemName: "magnifyingglass")
                            .font(.title3)
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.cyan, .blue],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .symbolEffect(.pulse, options: .repeating, value: !isAnalysisComplete)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(query)
                            .font(.title3)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                    }

                    Spacer()
                }
                .padding(16)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))

            case nil:
                EmptyView()
            }

            if let error = state.analysisError {
                InlineErrorBanner(
                    error: error,
                    onRetry: {
                        state.retryAIAnalysis()
                    },
                    onCancel: {
                        onCancel()
                    }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: state.analysisError)
    }
}
