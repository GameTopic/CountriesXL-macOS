import Foundation
import Combine
import SwiftUI

@MainActor
final class SettingsService: ObservableObject {
    static let shared = SettingsService()
    @Published var settings: SettingsModel = SettingsModel()
    private let defaultsKey = "SettingsModel.v1"
    private var cancellables = Set<AnyCancellable>()

    private init() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let decoded = try? JSONDecoder().decode(SettingsModel.self, from: data) {
            self.settings = decoded
        }
        // Persist on change
        $settings
            .removeDuplicates()
            .sink { [weak self] newValue in
                guard let self else { return }
                if let data = try? JSONEncoder().encode(newValue) {
                    UserDefaults.standard.set(data, forKey: self.defaultsKey)
                }
            }
            .store(in: &cancellables)
    }

    func update(_ mutate: (inout SettingsModel) -> Void) {
        var copy = settings
        mutate(&copy)
        if copy != settings { settings = copy }
    }
}
