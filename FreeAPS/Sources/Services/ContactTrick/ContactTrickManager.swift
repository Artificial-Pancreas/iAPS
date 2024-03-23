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
    private var state = ContactTrickState()
    private let contactStore = CNContactStore()
    private var workItem: DispatchWorkItem?

    @Injected() private var broadcaster: Broadcaster!
    @Injected() private var settingsManager: SettingsManager!
    @Injected() private var storage: FileStorage!

    private var contacts: [ContactTrickEntry] = []

    let coreDataStorage = CoreDataStorage()

    init(resolver: Resolver) {
        super.init()
        injectServices(resolver)

        contacts = storage.retrieve(OpenAPS.Settings.contactTrick, as: [ContactTrickEntry].self)
            ?? [ContactTrickEntry](from: OpenAPS.defaults(for: OpenAPS.Settings.contactTrick))
            ?? []

        broadcaster.register(GlucoseObserver.self, observer: self)
        broadcaster.register(SuggestionObserver.self, observer: self)
        broadcaster.register(SettingsObserver.self, observer: self)

        configureState()
    }

    func updateContacts(contacts: [ContactTrickEntry], completion: @escaping (Result<Void, Error>) -> Void) {
        processQueue.async {
            self.contacts = contacts
            self.renderContacts()
            completion(.success(()))
        }
    }

    private func configureState() {
        processQueue.async {
            let readings = self.coreDataStorage.fetchGlucose(interval: DateFilter().twoHours)
            let glucoseValues = self.glucoseText(readings)
            self.state.glucose = glucoseValues.glucose
            self.state.trend = glucoseValues.trend
            self.state.delta = glucoseValues.delta
            self.state.glucoseDate = readings.first?.date ?? .distantPast
            self.state.lastLoopDate = self.suggestion?.timestamp

            self.state.iob = self.suggestion?.iob
            self.state.cob = self.suggestion?.cob
            self.state.maxIOB = self.settingsManager.preferences.maxIOB
            self.state.maxCOB = self.settingsManager.preferences.maxCOB

            self.state.eventualBG = self.eventualBGString()

            self.renderContacts()
        }
    }

    private func renderContacts() {
        contacts.forEach { renderContact($0) }
        workItem = DispatchWorkItem(block: {
            print("in updateContact, no updates received for more than 5 minutes")
            self.renderContacts()
        })
        DispatchQueue.main.asyncAfter(deadline: .now() + 5 * 60 + 15, execute: workItem!)
    }

    private func renderContact(_ entry: ContactTrickEntry) {
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

    private func eventualBGString() -> String? {
        guard let eventualBG = suggestion?.eventualBG else {
            return nil
        }
        let units = settingsManager.settings.units
        return eventualFormatter.string(
            from: (units == .mmolL ? eventualBG.asMmolL : Decimal(eventualBG)) as NSNumber
        )!
    }

    private var glucoseFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "en_US")
        formatter.maximumFractionDigits = 0
        if settingsManager.settings.units == .mmolL {
            formatter.minimumFractionDigits = 1
            formatter.maximumFractionDigits = 1
        }
        formatter.roundingMode = .halfUp
        return formatter
    }

    private var eventualFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        return formatter
    }

    private var deltaFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        formatter.positivePrefix = "+"
        return formatter
    }

    private var suggestion: Suggestion? {
        storage.retrieve(OpenAPS.Enact.suggested, as: Suggestion.self)
    }
}

extension BaseContactTrickManager:
    GlucoseObserver,
    SuggestionObserver,
    SettingsObserver
{
    func glucoseDidUpdate(_: [BloodGlucose]) {
        configureState()
    }

    func suggestionDidUpdate(_: Suggestion) {
        configureState()
    }

    func settingsDidChange(_: FreeAPSSettings) {
        configureState()
    }
}
