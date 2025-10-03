import SwiftUI

func removePumpManagerActionSheet(deleteAction: @escaping () -> Void) -> ActionSheet {
    ActionSheet(
        title: Text(LocalizedString("Remove Pump", comment: "Title for PumpManager deletion action sheet.")),
        message: Text(LocalizedString(
            "Are you sure you want to stop using Medtrum TouchCare Nano 200u/300u?",
            comment: "Message for PumpManager deletion action sheet"
        )),
        buttons: [
            .destructive(Text(LocalizedString(
                "Delete pump",
                comment: "Button text to confirm PumpManager deletion"
            ))) {
                deleteAction()
            },
            .cancel()
        ]
    )
}
