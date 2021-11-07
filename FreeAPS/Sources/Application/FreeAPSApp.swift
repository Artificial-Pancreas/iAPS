import SwiftUI
import Swinject

@main struct FreeAPSApp: App {
	@Environment(\.scenePhase) var scenePhase

	// Dependencies Assembler
	// contain all dependencies Assemblies
	// TODO: Remove static key after update "Use Dependencies" logic
	private static var assembler = Assembler([
		StorageAssembly(),
		ServiceAssembly(),
		APSAssembly(),
		NetworkAssembly(),
		UIAssembly(),
		SecurityAssembly()
	])

	var resolver: Resolver {
		FreeAPSApp.assembler.resolver
	}

	// Temp static var
	// Use to backward compatibility with old Dependencies logic on Logger
	// TODO: Remove var after update "Use Dependencies" logic in Logger
	static var resolver: Resolver {
		FreeAPSApp.assembler.resolver
	}

	private func loadServices() {
		resolver.resolve(AppearanceManager.self)!.setupGlobalAppearance()
		_ = resolver.resolve(DeviceDataManager.self)!
		_ = resolver.resolve(APSManager.self)!
		_ = resolver.resolve(FetchGlucoseManager.self)!
		_ = resolver.resolve(FetchTreatmentsManager.self)!
		_ = resolver.resolve(FetchAnnouncementsManager.self)!
	}

	init() {
		loadServices()
	}

	var body: some Scene {
		WindowGroup {
			Main.Builder(resolver: resolver).buildView()
		}
		.onChange(of: scenePhase) { newScenePhase in
			switch newScenePhase {
			case .active:
				debug(.default, "APPLICATION is active")
			case .inactive:
				debug(.default, "APPLICATION is inactive")
			case .background:
				debug(.default, "APPLICATION is in background")
			@unknown default:
				debug(.default, "APPLICATION: Received an unexpected scenePhase.")
			}
		}
	}
}
