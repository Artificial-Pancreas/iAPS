//
//  DeliveryUncertaintyRecoveryView.swift
//  OmniBLE
//
//  Created by Pete Schwamb on 8/17/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import SwiftUI
import LoopKitUI

struct DeliveryUncertaintyRecoveryView: View {
    
    let model: DeliveryUncertaintyRecoveryViewModel

    init(model: DeliveryUncertaintyRecoveryViewModel) {
        self.model = model
    }

    var body: some View {
        GuidePage(content: {
            Text(String(format: LocalizedString("%1$@ has been unable to communicate with the pod on your body since %2$@.\n\nWithout communication with the pod, the app cannot continue to send commands for insulin delivery or display accurate, recent information about your active insulin or the insulin being delivered by the Pod.\n\nMonitor your glucose closely for the next 6 or more hours, as there may or may not be insulin actively working in your body that %3$@ cannot display.", comment: "Format string for main text of delivery uncertainty recovery page. (1: app name)(2: date of command)(3: app name)"), self.model.appName, self.uncertaintyDateLocalizedString, self.model.appName))
                .padding([.top, .bottom])
        }) {
            VStack {
                Text(LocalizedString("Attemping to re-establish communication", comment: "Description string above progress indicator while attempting to re-establish communication from an unacknowledged command")).padding(.top)
                ProgressIndicatorView(state: .indeterminantProgress)
                Button(action: {
                    self.model.podDeactivationChosen()
                }) {
                    Text(LocalizedString("Deactivate Pod", comment: "Button title to deactive pod on uncertain program"))
                    .actionButtonStyle(.destructive)
                    .padding()
                }
            }
        }
        .navigationBarTitle(Text(LocalizedString("Unable to Reach Pod", comment: "Title of delivery uncertainty recovery page")), displayMode: .large)
        .navigationBarItems(leading: backButton)
    }
    
    private var uncertaintyDateLocalizedString: String {
        DateFormatter.localizedString(from: model.uncertaintyStartedAt, dateStyle: .none, timeStyle: .short)
    }
    
    private var backButton: some View {
        Button(LocalizedString("Back", comment: "Back button text on DeliveryUncertaintyRecoveryView"), action: {
            self.model.onDismiss?()
        })
    }
}

struct DeliveryUncertaintyRecoveryView_Previews: PreviewProvider {
    static var previews: some View {
        let model = DeliveryUncertaintyRecoveryViewModel(appName: "Test App", uncertaintyStartedAt: Date())
        return DeliveryUncertaintyRecoveryView(model: model)
    }
}
