//
//  LoadingModal.swift
//  DanaKit
//
//  Created by Bastiaan Verhaar on 03/01/2024.
//  Copyright © 2024 Randall Knutson. All rights reserved.
//
// Source: https://blog.appdeco.ca/2020/07/27/create-progressview-modal-in-swiftui/

import SwiftUI

struct LoadingModal<Content>: View where Content: View {

    @Environment(\.colorScheme) var colorScheme
    
    @Binding var isShowing: Bool
    var text: String?
    var content: () -> Content
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .center) {
                content()
                    .disabled(isShowing)
                    .blur(radius: isShowing ? 2 : 0)
                
                if isShowing {
                    // this Rectangle is a semi-transparent black overlay
                    Rectangle()
                        .fill(Color.black).opacity(isShowing ? 0.3 : 0)
                        .edgesIgnoringSafeArea(.all)

                    VStack(spacing: 24) {
                        ProgressView()
                        Text(text ?? LocalizedString("loading", comment: "Generic loading text")).font(.headline)
                    }
                    .frame(width: 250, height: 200)
                    .background(colorScheme == .light ? Color.white : Color.black)
                    .foregroundColor(Color.primary)
                    .cornerRadius(16)
                }
            }
        }
    }
}
#Preview {
    @State var loadingViewShowing = false
    
    return LoadingModal(isShowing: $loadingViewShowing) {
            Button(action: {
                loadingViewShowing = true
                // Mock some network request or other task
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    loadingViewShowing = false
                }
            }, label: {
                Text("Tap Me!")
            })
        }
}
