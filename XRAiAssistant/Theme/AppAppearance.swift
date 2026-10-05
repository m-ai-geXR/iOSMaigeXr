//
//  AppAppearance.swift
//  m{ai}geXR
//
//  How the app picks light or dark.
//
//  The brand palette is adaptive, so following the system needs no setting at
//  all. This exists because following the system is not always what a person
//  wants: the desktop client has offered System, Light and Dark since the brand
//  work, and the native clients had no way to override at all.
//

import SwiftUI

enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    /// nil means "follow the system", which is what SwiftUI does when
    /// preferredColorScheme is absent.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// Owns the appearance setting.
///
/// The root scene needs the value, but ChatViewModel lives inside ContentView
/// and cannot be reached from there. Reading the raw UserDefaults key with
/// @AppStorage looked like the way around that, and did not work reliably — the
/// root did not observe writes made elsewhere. A small shared object both sides
/// can observe is simpler and actually updates.
@MainActor
final class AppearanceStore: ObservableObject {
    static let shared = AppearanceStore()

    private static let key = "XRAiAssistant_Appearance"

    @Published var appearance: AppAppearance {
        didSet {
            guard oldValue != appearance else { return }
            UserDefaults.standard.set(appearance.rawValue, forKey: Self.key)
        }
    }

    private init() {
        let saved = UserDefaults.standard.string(forKey: Self.key)
        appearance = saved.flatMap(AppAppearance.init(rawValue:)) ?? .system
    }
}
