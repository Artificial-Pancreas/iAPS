//
//  PlayTestBeepsView.swift
//  OmniBLE
//
//  Created by Joe Moran on 9/1/23.
//  Copyright © 2023 LoopKit Authors. All rights reserved.
//

import SwiftUI
import LoopKit


struct PlayTestBeepsView: View {
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.presentationMode) var presentationMode: Binding<PresentationMode>

    var playTestBeeps: () async throws -> Void

    private let title = LocalizedString("Play Test Beeps", comment: "navigation title for play test beeps")
    private let actionString = LocalizedString("Playing Test Beeps...", comment: "button title when executing play test beeps")
    private let failedString: String = LocalizedString("Failed to play test beeps.", comment: "Alert title for error when playing test beeps")
    private let successMessage = LocalizedString("Play test beeps command sent successfully.\n\nIf you did not hear any beeps from your Pod, the piezo speaker in your Pod may be broken or disabled.", comment: "Success message for play test beeps")

    @State private var alertIsPresented: Bool = false
    @State private var displayString: String = ""
    @State private var error: Error? = nil
    @State private var executing: Bool = false
    @State private var showActivityView = false

    var body: some View {
        VStack {
            List {
                Section {
                    Text(self.displayString).fixedSize(horizontal: false, vertical: true)
                }
            }
            VStack {
                Button(action: {
                    Task { await playTestBeepsAndHandleError() }
                }) {
                    Text(buttonText)
                        .actionButtonStyle(.primary)
                }
                .padding()
                .disabled(executing)
            }
            .padding(self.horizontalSizeClass == .regular ? .bottom : [])
            .background(Color(UIColor.secondarySystemGroupedBackground).shadow(radius: 5))
        }
        .insetGroupedListStyle()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .alert(isPresented: $alertIsPresented, content: { alert(error: error) })
        .task {
            await playTestBeepsAndHandleError()
        }
    }

    private func playTestBeepsAndHandleError() async {
        do {
            try await playTestBeeps()
            self.displayString = successMessage
        } catch {
            self.displayString = ""
            self.error = error
            self.alertIsPresented = true
        }
    }

    private var buttonText: String {
        if executing {
            return actionString
        } else {
            return title
        }
    }

    private func alert(error: Error?) -> SwiftUI.Alert {
        return SwiftUI.Alert(
            title: Text(failedString),
            message: Text(error?.localizedDescription ?? "No Error")
        )
    }
}

struct PlayTestBeepsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            PlayTestBeepsView {
                print("Beep!")
            }
        }
    }
}
