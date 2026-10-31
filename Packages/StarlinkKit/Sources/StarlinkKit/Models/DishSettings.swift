import Foundation

public enum SnowMeltMode: Int, Sendable, Codable, CaseIterable, Identifiable {
    case auto = 0, alwaysOn = 1, alwaysOff = 2
    public var id: Int { rawValue }
    public var label: String { ["Auto", "Always on", "Always off"][rawValue] }
}

public enum DishLevelMode: Int, Sendable, Codable, CaseIterable, Identifiable {
    case tiltNormally = 0, forceLevel = 1
    public var id: Int { rawValue }
    public var label: String { self == .tiltNormally ? "Tilt normally" : "Force level" }
}

/// The user-facing subset of `DishConfig`.
public struct DishSettings: Sendable, Equatable, Codable {
    public var snowMelt: SnowMeltMode
    public var levelDish: DishLevelMode
    public var powerSave: Bool
    public var powerSaveStartMinutes: Int       // minutes after midnight UTC
    public var powerSaveDurationMinutes: Int
    public var threeDayDeferral: Bool
    public var updateRebootHour: Int            // local hour 0-23
    public init(snowMelt: SnowMeltMode = .auto, levelDish: DishLevelMode = .tiltNormally, powerSave: Bool = false,
                powerSaveStartMinutes: Int = 0, powerSaveDurationMinutes: Int = 0, threeDayDeferral: Bool = false,
                updateRebootHour: Int = 3) {
        self.snowMelt = snowMelt; self.levelDish = levelDish; self.powerSave = powerSave
        self.powerSaveStartMinutes = powerSaveStartMinutes; self.powerSaveDurationMinutes = powerSaveDurationMinutes
        self.threeDayDeferral = threeDayDeferral; self.updateRebootHour = updateRebootHour
    }
}

/// One dish write. Each case sets exactly one field plus its `apply_` flag (see `DishService`).
public enum DishSetting: Sendable, Equatable {
    case snowMelt(SnowMeltMode)
    case levelDish(DishLevelMode)
    case powerSave(Bool)
    case powerSaveWindow(startMinutes: Int, durationMinutes: Int)
    case threeDayDeferral(Bool)
    case updateRebootHour(Int)

    public var title: String {
        switch self {
        case .snowMelt: "Snow melt"
        case .levelDish: "Dish levelling"
        case .powerSave: "Sleep schedule"
        case .powerSaveWindow: "Sleep window"
        case .threeDayDeferral: "Defer updates 3 days"
        case .updateRebootHour: "Update reboot hour"
        }
    }

    public func value(in s: DishSettings) -> DishSetting {
        switch self {
        case .snowMelt: .snowMelt(s.snowMelt)
        case .levelDish: .levelDish(s.levelDish)
        case .powerSave: .powerSave(s.powerSave)
        case .powerSaveWindow: .powerSaveWindow(startMinutes: s.powerSaveStartMinutes, durationMinutes: s.powerSaveDurationMinutes)
        case .threeDayDeferral: .threeDayDeferral(s.threeDayDeferral)
        case .updateRebootHour: .updateRebootHour(s.updateRebootHour)
        }
    }

    public var displayValue: String {
        switch self {
        case .snowMelt(let m): m.label
        case .levelDish(let m): m.label
        case .powerSave(let b), .threeDayDeferral(let b): b ? "On" : "Off"
        case .powerSaveWindow(let s, let d): "\(s / 60):\(String(format: "%02d", s % 60)) UTC for \(d / 60)h \(d % 60)m"
        case .updateRebootHour(let h): "\(h):00"
        }
    }
}
