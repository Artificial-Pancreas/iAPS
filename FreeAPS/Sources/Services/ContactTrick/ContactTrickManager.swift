import Algorithms
import Combine
import Contacts
import Foundation
import Swinject

protocol ContactTrickManager {
    func updateContacts(contacts: [ContactTrickEntry], completion: @escaping (Result<Void, Error>) -> Void)
}

final class BaseContactTrickManager: NSObject, ContactTrickManager, Injectable {
    private let processQueue = DispatchQueue(label: "BaseContactTrickManager.processQueue")
    private let contactStore = CNContactStore()
    private var workItem: DispatchWorkItem?

    @Injected() private var broadcaster: Broadcaster!
    @Injected() private var settingsManager: SettingsManager!
    @Injected() private var storage: FileStorage!

    private var contacts: [ContactTrickEntry] = []

    private let coreDataStorage = CoreDataStorage()

    init(resolver: Resolver) {
        super.init()
        injectServices(resolver)

        broadcaster.register(SuggestionObserver.self, observer: self)
        broadcaster.register(SettingsObserver.self, observer: self)

        contacts = storage.retrieve(OpenAPS.Settings.contactTrick, as: [ContactTrickEntry].self)
            ?? [ContactTrickEntry](from: OpenAPS.defaults(for: OpenAPS.Settings.contactTrick))
            ?? []

        processQueue.async {
            self.renderContacts()
        }
    }

    func updateContacts(contacts: [ContactTrickEntry], completion: @escaping (Result<Void, Error>) -> Void) {
        self.contacts = contacts

        processQueue.async {
            self.renderContacts()
            completion(.success(()))
        }
    }

    private func renderContacts() {
        if let workItem = workItem, !workItem.isCancelled {
            workItem.cancel()
        }

        let readings = coreDataStorage.fetchGlucose(interval: DateFilter().twoHours)
        let glucoseValues = glucoseText(readings)

        let suggestion: Suggestion? = storage.retrieve(OpenAPS.Enact.suggested, as: Suggestion.self)

        let state = ContactTrickState(
            glucose: bgString(suggestion),
            trend: glucoseValues.trend,
            delta: glucoseValues.delta,
            lastLoopDate: suggestion?.timestamp,
            iob: suggestion?.iob,
            iobText: suggestion?.iob.map { iob in
                iobFormatter.string(from: iob as NSNumber)!
            },
            cob: suggestion?.cob,
            cobText: suggestion?.cob.map { cob in
                cobFormatter.string(from: cob as NSNumber)!
            },
            eventualBG: eventualBGString(suggestion),
            maxIOB: settingsManager.preferences.maxIOB,
            maxCOB: settingsManager.preferences.maxCOB
        )

        contacts.forEach { renderContact($0, state) }

        workItem = DispatchWorkItem(block: {
            print("in updateContact, no updates received for more than 5 minutes")
            self.renderContacts()
        })
        DispatchQueue.main.asyncAfter(deadline: .now() + 5 * 60 + 15, execute: workItem!)
    }

    private func renderContact(_ entry: ContactTrickEntry, _ state: ContactTrickState) {
        guard let contactId = entry.contactId, entry.enabled else {
            return
        }

        let keysToFetch = [CNContactImageDataKey] as [CNKeyDescriptor]

        let contact: CNContact
        do {
            contact = try contactStore.unifiedContact(withIdentifier: contactId, keysToFetch: keysToFetch)
        } catch {
            print("in updateContact, an error has been thrown while fetching the selected contact")
            return
        }

        guard let mutableContact = contact.mutableCopy() as? CNMutableContact else {
            return
        }

        mutableContact.imageData = ContactPicture.getImage(
            contact: entry,
            state: state
        ).pngData()

        saveUpdatedContact(mutableContact)
    }

    private func saveUpdatedContact(_ mutableContact: CNMutableContact) {
        let saveRequest = CNSaveRequest()
        saveRequest.update(mutableContact)
        do {
            try contactStore.execute(saveRequest)
        } catch let error as NSError {
            var details: String?
            if error.domain == CNErrorDomain {
                switch error.code {
                case CNError.authorizationDenied.rawValue:
                    details = "Authorization denied"
                case CNError.communicationError.rawValue:
                    details = "Communication error"
                case CNError.insertedRecordAlreadyExists.rawValue:
                    details = "Record already exists"
                case CNError.dataAccessError.rawValue:
                    details = "Data access error"
                default:
                    details = "Code \(error.code)"
                }
            }
            print("in updateContact, failed to update the contact - \(details ?? "no details"): \(error.localizedDescription)")

        } catch {
            print("in updateContact, failed to update the contact: \(error.localizedDescription)")
        }
    }

    private func glucoseText(_ glucose: [Readings]) -> (glucose: String, trend: String, delta: String) {
        let glucoseValue = glucose.first?.glucose ?? 0

        guard !glucose.isEmpty else { return ("--", "--", "--") }

        let delta = glucose.count >= 2 ? glucoseValue - glucose[1].glucose : nil

        let units = settingsManager.settings.units
        let glucoseText = glucoseFormatter
            .string(from: Double(
                units == .mmolL ? Decimal(glucoseValue).asMmolL : Decimal(glucoseValue)
            ) as NSNumber)!

        let directionText = glucose.first?.direction ?? "↔︎"
        let deltaText = delta
            .map {
                self.deltaFormatter
                    .string(from: Double(
                        units == .mmolL ? Decimal($0).asMmolL : Decimal($0)
                    ) as NSNumber)!
            } ?? "--"

        return (glucoseText, directionText, deltaText)
    }

    private func bgString(_ suggestion: Suggestion?) -> String? {
        guard let bg = suggestion?.bg else {
            return nil
        }
        let units = settingsManager.settings.units
        return glucoseFormatter.string(
            from: (units == .mmolL ? bg.asMmolL : bg) as NSNumber
        )!
    }

    private func eventualBGString(_ suggestion: Suggestion?) -> String? {
        guard let eventualBG = suggestion?.eventualBG else {
            return nil
        }
        let units = settingsManager.settings.units
        return glucoseFormatter.string(
            from: (units == .mmolL ? eventualBG.asMmolL : Decimal(eventualBG)) as NSNumber
        )!
    }

    private var glucoseFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        if settingsManager.settings.units == .mmolL {
            formatter.minimumFractionDigits = 1
            formatter.maximumFractionDigits = 1
        }
        formatter.roundingMode = .halfUp
        return formatter
    }

    private var iobFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 1
        formatter.roundingMode = .halfUp
        return formatter
    }

    private var cobFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        formatter.roundingMode = .halfUp
        return formatter
    }

    private var deltaFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        formatter.positivePrefix = "+"
        return formatter
    }
}

extension BaseContactTrickManager:
    SuggestionObserver,
    SettingsObserver
{
    func suggestionDidUpdate(_: Suggestion) {
        renderContacts()
    }

    func settingsDidChange(_: FreeAPSSettings) {
        renderContacts()
    }
}
