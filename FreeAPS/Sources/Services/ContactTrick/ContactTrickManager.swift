import Contacts
import Swinject

protocol ContactTrickManager: Sendable {
    func updateContacts(contacts: [ContactTrickEntry]) async -> [ContactTrickEntry]
    var currentContacts: [ContactTrickEntry] { get async }
}

actor BaseContactTrickManager: ContactTrickManager, Injectable, LifetimeOwner, AppService {
    private let contactStore = CNContactStore()

    private var staleRenderTask: Task<Void, Never>?

    private let appCoordinator: AppCoordinator
    private let storage: FileStorage

    private var knownIds: [String] = []
    private var contacts: [ContactTrickEntry] = []

    var currentContacts: [ContactTrickEntry] {
        contacts
    }

    private let coreDataStorage = CoreDataStorage()

    let lifetime = Lifetime()

    init(
        appCoordinator: AppCoordinator,
        storage: FileStorage
    ) {
        self.appCoordinator = appCoordinator
        self.storage = storage
    }

    // this is called at the start of the app
    func start() async {
        contacts = await storage.retrieve(OpenAPS.Settings.contactTrick, as: [ContactTrickEntry].self)
            ?? [ContactTrickEntry](from: OpenAPS.defaults(for: OpenAPS.Settings.contactTrick))
            ?? []

        knownIds = contacts.compactMap(\.contactId)

        observe(appCoordinator.settings.dropFirst()) { me, _ in
            await me.renderContacts(forceSave: false)
        }
        observe(appCoordinator.preferences.dropFirst()) { me, _ in
            await me.renderContacts(forceSave: false)
        }
        observe(appCoordinator.loopCompleted) { me, _ in
            await me.renderContacts(forceSave: false)
        }
        observe(appCoordinator.iobTicks.dropFirst()) { me, _ in
            await me.renderContacts(forceSave: false)
        }

        await self.renderContacts(forceSave: false)
    }

    func updateContacts(contacts: [ContactTrickEntry]) async -> [ContactTrickEntry] {
        self.contacts = contacts
        let newIds = contacts.compactMap(\.contactId)

        let knownSet = Set(knownIds)
        let newSet = Set(newIds)
        let removedIds = knownSet.subtracting(newSet)

        removedIds.forEach { contactId in
            if !self.deleteContact(contactId) {
                debug(.service, "contacts cleanup, failed to delete contact \(contactId)")
            }
        }
        await self.renderContacts(forceSave: true)
        self.knownIds = self.contacts.compactMap(\.contactId)
        return self.contacts
    }

    private func renderContacts(forceSave: Bool) async {
        staleRenderTask?.cancel()

        let settings = appCoordinator.settings.value
        let preferences = appCoordinator.preferences.value

        guard contacts.isNotEmpty, CNContactStore.authorizationStatus(for: .contacts) == .authorized else {
            return
        }

        let suggestion = appCoordinator.latestLoopOutcome.value?.suggestion

        let readings = await coreDataStorage.fetchGlucose(interval: DateFilter.twoHours.startDate)
        let glucoseValues = glucoseText(readings, settings: settings)

        let iob = appCoordinator.iobTicks.value?.first?.iob ?? suggestion?.iob
        let state = ContactTrickState(
            glucose: glucoseValues.glucose,
            trend: glucoseValues.trend,
            delta: glucoseValues.delta,
            lastLoopDate: appCoordinator.lastLoopDate.value,
            iob: iob,
            iobText: iob.map { iob in
                Self.iobFormatter.string(from: iob as NSNumber)!
            },
            cob: suggestion?.cob,
            cobText: suggestion?.cob.map { cob in
                Self.cobFormatter.string(from: cob as NSNumber)!
            },
            eventualBG: eventualBGString(suggestion, settings: settings),
            maxIOB: preferences.maxIOB,
            maxCOB: preferences.maxCOB
        )

        let newContacts = contacts.enumerated().map { index, entry in renderContact(entry, index + 1, state) }

        if forceSave || newContacts != contacts {
            // when we create new contacts we store the IDs, in that case we need to write into the settings storage
            await storage.save(newContacts, as: OpenAPS.Settings.contactTrick)
        }
        contacts = newContacts

        staleRenderTask = Task {
            try? await Task.sleep(for: .seconds(5 * 60 + 15))
            guard !Task.isCancelled else { return }
            debug(.service, "in renderContacts, no updates received for more than 5 minutes")
            await self.renderContacts(forceSave: false)
        }
    }

    private let keysToFetch = [
        CNContactImageDataKey,
        CNContactGivenNameKey,
        CNContactOrganizationNameKey
    ] as [CNKeyDescriptor]

    private func renderContact(_ _entry: ContactTrickEntry, _ index: Int, _ state: ContactTrickState) -> ContactTrickEntry {
        var entry = _entry
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
                    debug(.service, "in handleEnabledContact, failed to fetch the contact, code 200, contact does not exist")
                    mutableContact = createNewContact(
                        entry: entry,
                        index: index,
                        state: state,
                        saveRequest: saveRequest
                    )
                } else {
                    debug(.service, "in handleEnabledContact, failed to fetch the contact - \(getContactsErrorDetails(error))")
                    return entry
                }
            } catch {
                debug(.service, "in handleEnabledContact, failed to fetch the contact: \(error.localizedDescription)")
                return entry
            }

        } else {
            debug(.service, "no contact \(index) - creating")
            mutableContact = createNewContact(
                entry: entry,
                index: index,
                state: state,
                saveRequest: saveRequest
            )
        }

        saveUpdatedContact(saveRequest)

        entry.contactId = mutableContact.identifier

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
        debug(.service, "creating a new contact, \(mutableContact.identifier)")
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
        mutableContact
            .organizationName =
            "Created and managed by iAPS - \(Date().formatted(date: .abbreviated, time: .shortened))"

        mutableContact.imageData = ContactPicture.getImage(
            contact: entry,
            state: state
        ).pngData()
    }

    private func deleteContact(_ contactId: String) -> Bool {
        do {
            debug(.service, "deleting contact \(contactId)")
            let keysToFetch = [CNContactIdentifierKey as CNKeyDescriptor] // we don't really need any, so just ID
            let contact = try contactStore.unifiedContact(withIdentifier: contactId, keysToFetch: keysToFetch)

            guard let mutableContact = contact.mutableCopy() as? CNMutableContact else {
                debug(.service, "in deleteContact, failed to get a mutable copy of the contact")
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
                debug(.service, "in deleteContact, failed to delete the contact - \(getContactsErrorDetails(error))")
                return false
            }
        } catch {
            debug(.service, "in deleteContact, failed to delete the contact: \(error.localizedDescription)")
            return false
        }
    }

    private func saveUpdatedContact(_ saveRequest: CNSaveRequest) {
        do {
            try contactStore.execute(saveRequest)
        } catch let error as NSError {
            debug(.service, "in updateContact, failed to update the contact - \(getContactsErrorDetails(error))")
        } catch {
            debug(.service, "in updateContact, failed to update the contact: \(error.localizedDescription)")
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

    private func glucoseText(
        _ glucose: [ReadingsSnapshot],
        settings: FreeAPSSettings
    ) -> (glucose: String, trend: String, delta: String) {
        guard !glucose.isEmpty else { return ("--", "--", "--") }

        let glucoseValue = glucose.first?.glucose ?? 0
        let delta = glucose.count >= 2 ? glucoseValue - glucose[1].glucose : nil

        let units = settings.units
        let glucoseText = Self.glucoseFormatter(settings: settings)
            .string(from: (
                units == .mmolL ? Decimal(glucoseValue).asMmolL : Decimal(glucoseValue)
            ) as NSNumber)!

        let directionText = glucose.first?.direction ?? "↔︎"
        let deltaText = delta
            .map {
                Self.deltaFormatter
                    .string(from: (
                        units == .mmolL ? Decimal($0).asMmolL : Decimal($0)
                    ) as NSNumber)!
            } ?? "--"

        return (glucoseText, directionText, deltaText)
    }

    private func eventualBGString(_ suggestion: Suggestion?, settings: FreeAPSSettings) -> String? {
        guard let eventualBG = suggestion?.eventualBG else {
            return nil
        }
        let units = settings.units
        return Self.glucoseFormatter(settings: settings).string(
            from: (units == .mmolL ? eventualBG.asMmolL : Decimal(eventualBG)) as NSNumber
        )!
    }

    private static let glucoseFormatterMmolL = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 1
        formatter.roundingMode = .halfUp
        return formatter
    }()

    private static let glucoseFormatterMgDl = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        formatter.roundingMode = .halfUp
        return formatter
    }()

    private static func glucoseFormatter(settings: FreeAPSSettings) -> NumberFormatter {
        switch settings.units {
        case .mmolL: return glucoseFormatterMmolL
        case .mgdL: return glucoseFormatterMgDl
        }
    }

    private static let iobFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 1
        formatter.roundingMode = .halfUp
        return formatter
    }()

    private static let cobFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        formatter.roundingMode = .halfUp
        return formatter
    }()

    private static let deltaFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        formatter.positivePrefix = "+"
        return formatter
    }()
}
