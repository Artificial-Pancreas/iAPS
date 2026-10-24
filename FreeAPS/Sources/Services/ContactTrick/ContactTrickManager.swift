import Algorithms
import Combine
import Contacts
import Foundation
import Swinject

protocol ContactTrickManager {
    func updateContacts(contacts: [ContactTrickEntry], completion: @escaping (Result<[ContactTrickEntry], Error>) -> Void)
    var currentContacts: [ContactTrickEntry] { get }
}

/// all rendering happens on the main queue (observers are notified there, and the glucose readings
/// come from the main Core Data context), so renders never overlap
final class BaseContactTrickManager: NSObject, ContactTrickManager, Injectable {
    private static let organizationName = "Created and managed by iAPS"

    private let contactStore = CNContactStore()
    private var workItem: DispatchWorkItem?

    @Injected() private var broadcaster: Broadcaster!
    @Injected() private var settingsManager: SettingsManager!
    @Injected() private var storage: FileStorage!

    private var knownIds: [String] = []
    private var contacts: [ContactTrickEntry] = []

    /// what each contact was last saved from, by contact id. Not persisted: every contact is saved once
    /// after launch, and after that only when its name or picture would change. Every save is synced
    /// through iCloud to all the user's devices, so saving an unchanged contact is not free.
    private var renderedFrom: [String: RenderInput] = [:]

    private struct RenderInput: Equatable {
        let index: Int
        let picture: ContactPicture.Input
    }

    var currentContacts: [ContactTrickEntry] {
        contacts
    }

    private let coreDataStorage = CoreDataStorage()

    init(resolver: Resolver) {
        super.init()
        injectServices(resolver)

        broadcaster.register(SuggestionObserver.self, observer: self)
        broadcaster.register(SettingsObserver.self, observer: self)

        contacts = storage.retrieve(OpenAPS.Settings.contactTrick, as: [ContactTrickEntry].self)
            ?? [ContactTrickEntry](from: OpenAPS.defaults(for: OpenAPS.Settings.contactTrick))
            ?? []

        knownIds = contacts.compactMap(\.contactId)

        DispatchQueue.main.async {
            self.renderContacts(forceSave: false)
        }
    }

    func updateContacts(contacts: [ContactTrickEntry], completion: @escaping (Result<[ContactTrickEntry], Error>) -> Void) {
        DispatchQueue.main.async {
            self.contacts = contacts
            let newIds = contacts.compactMap(\.contactId)

            let knownSet = Set(self.knownIds)
            let newSet = Set(newIds)
            let removedIds = knownSet.subtracting(newSet)

            for contactId in removedIds {
                self.renderedFrom[contactId] = nil
                if !self.deleteContact(contactId) {
                    print("contacts cleanup, failed to delete contact \(contactId)")
                }
            }
            self.renderContacts(forceSave: true)
            self.knownIds = self.contacts.compactMap(\.contactId)
            completion(.success(self.contacts))
        }
    }

    private func renderContacts(forceSave: Bool) {
        if let workItem = workItem, !workItem.isCancelled {
            workItem.cancel()
        }

        var newContacts = contacts

        if contacts.isNotEmpty, CNContactStore.authorizationStatus(for: .contacts) == .authorized {
            let readings = coreDataStorage.fetchGlucose(interval: DateFilter.twoHours.startDate)
            let glucoseValues = glucoseText(readings)

            let suggestion: Suggestion? = storage.retrieve(OpenAPS.Enact.suggested, as: Suggestion.self)

            let state = ContactTrickState(
                glucose: glucoseValues.glucose,
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

            // a disabled contact is kept (so a watch face pointing at it still works when it is enabled again),
            // but drawn without any values, so that it doesn't show stale data as if it were live.
            // Its picture doesn't change after that, so it is saved only once.
            newContacts = contacts.enumerated().map { index, entry in
                renderContact(entry, index + 1, entry.enabled ? state : ContactTrickState())
            }
        }

        // this is outside of the check above so that an empty list (the last entry deleted) is persisted too
        if forceSave || newContacts != contacts {
            // when we create new contacts we store the IDs, in that case we need to write into the settings storage
            storage.save(newContacts, as: OpenAPS.Settings.contactTrick)
        }
        contacts = newContacts

        workItem = DispatchWorkItem(block: {
            print("in renderContacts, no updates received for more than 5 minutes")
            self.renderContacts(forceSave: false)
        })
        DispatchQueue.main.asyncAfter(deadline: .now() + 5 * 60 + 15, execute: workItem!)
    }

    private let keysToFetch = [
        CNContactImageDataKey,
        CNContactGivenNameKey,
        CNContactOrganizationNameKey
    ] as [CNKeyDescriptor]

    private func renderContact(_ _entry: ContactTrickEntry, _ index: Int, _ state: ContactTrickState) -> ContactTrickEntry {
        var entry = _entry

        if let contactId = entry.contactId,
           renderedFrom[contactId] == RenderInput(index: index, picture: ContactPicture.input(contact: entry, state: state))
        {
            return entry
        }

        let mutableContact: CNMutableContact
        let saveRequest = CNSaveRequest()

        if let contactId = entry.contactId {
            do {
                let contact = try contactStore.unifiedContact(withIdentifier: contactId, keysToFetch: keysToFetch)

                mutableContact = contact.mutableCopy() as! CNMutableContact
                updateContactFields(entry: entry, index: index, state: state, mutableContact: mutableContact)
                saveRequest.update(mutableContact)
            } catch let error as NSError {
                if error.code == 200 { // 200: Updated Record Does Not Exist
                    print("in handleEnabledContact, failed to fetch the contact, code 200, contact does not exist")
                    mutableContact = createNewContact(
                        entry: entry,
                        index: index,
                        state: state,
                        saveRequest: saveRequest
                    )
                } else {
                    print("in handleEnabledContact, failed to fetch the contact - \(getContactsErrorDetails(error))")
                    return entry
                }
            } catch {
                print("in handleEnabledContact, failed to fetch the contact: \(error.localizedDescription)")
                return entry
            }

        } else {
            print("no contact \(index) - creating")
            mutableContact = createNewContact(
                entry: entry,
                index: index,
                state: state,
                saveRequest: saveRequest
            )
        }

        let saved = saveUpdatedContact(saveRequest)

        entry.contactId = mutableContact.identifier

        if saved {
            // built from the entry with its contact id set, which is how it comes in next time
            renderedFrom[mutableContact.identifier] = RenderInput(
                index: index,
                picture: ContactPicture.input(contact: entry, state: state)
            )
        }

        return entry
    }

    private func createNewContact(
        entry: ContactTrickEntry,
        index: Int,
        state: ContactTrickState,
        saveRequest: CNSaveRequest
    ) -> CNMutableContact {
        let mutableContact = CNMutableContact()
        updateContactFields(
            entry: entry, index: index, state: state, mutableContact: mutableContact
        )
        print("creating a new contact, \(mutableContact.identifier)")
        saveRequest.add(mutableContact, toContainerWithIdentifier: nil)
        return mutableContact
    }

    private func updateContactFields(
        entry: ContactTrickEntry,
        index: Int,
        state: ContactTrickState,
        mutableContact: CNMutableContact
    ) {
        mutableContact.givenName = "iAPS \(index)"
        mutableContact.organizationName = Self.organizationName

        mutableContact.imageData = ContactPicture.getImage(
            contact: entry,
            state: state
        ).pngData()
    }

    private func deleteContact(_ contactId: String) -> Bool {
        do {
            print("deleting contact \(contactId)")
            let keysToFetch = [CNContactIdentifierKey as CNKeyDescriptor] // we don't really need any, so just ID
            let contact = try contactStore.unifiedContact(withIdentifier: contactId, keysToFetch: keysToFetch)

            guard let mutableContact = contact.mutableCopy() as? CNMutableContact else {
                print("in deleteContact, failed to get a mutable copy of the contact")
                return false
            }

            let saveRequest = CNSaveRequest()
            saveRequest.delete(mutableContact)
            try contactStore.execute(saveRequest)
            return true
        } catch let error as NSError {
            if error.code == 200 { // Updated Record Does Not Exist
                return true
            } else {
                print("in deleteContact, failed to update the contact - \(getContactsErrorDetails(error))")
                return false
            }
        } catch {
            print("in deleteContact, failed to update the contact: \(error.localizedDescription)")
            return false
        }
    }

    private func saveUpdatedContact(_ saveRequest: CNSaveRequest) -> Bool {
        do {
            try contactStore.execute(saveRequest)
            return true
        } catch let error as NSError {
            print("in updateContact, failed to update the contact - \(getContactsErrorDetails(error))")
            return false
        } catch {
            print("in updateContact, failed to update the contact: \(error.localizedDescription)")
            return false
        }
    }

    private func getContactsErrorDetails(_ error: NSError) -> String {
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
        return "\(details ?? "no details"): \(error.localizedDescription)"
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
        renderContacts(forceSave: false)
    }

    func settingsDidChange(_: FreeAPSSettings) {
        renderContacts(forceSave: false)
    }
}
