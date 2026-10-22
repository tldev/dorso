import Foundation

// MARK: - Desk

/// A named camera calibration, kept per display configuration.
struct Desk: Codable, Identifiable, Equatable {
    let id: String
    var name: String
    var profile: ProfileData
}

private struct DeskSet: Codable, Equatable {
    var desks: [Desk]
    var activeDeskID: String

    var activeDesk: Desk? {
        desks.first(where: { $0.id == activeDeskID }) ?? desks.first
    }
}

// MARK: - Desk Store

/// Mirrors the active desk into the legacy `profiles` dictionary so older
/// builds keep working after a downgrade.
@MainActor
final class DeskStore {
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    // MARK: - Queries

    func desks(forKey key: String) -> [Desk] {
        loadSets()[key]?.desks ?? []
    }

    func activeDesk(forKey key: String) -> Desk? {
        loadSets()[key]?.activeDesk
    }

    func activeProfile(forKey key: String) -> ProfileData? {
        activeDesk(forKey: key)?.profile
    }

    func canDeleteDesk(forKey key: String) -> Bool {
        desks(forKey: key).count > 1
    }

    func nextDefaultName(forKey key: String) -> String {
        let existingNames = Set(desks(forKey: key).map(\.name))
        var index = 1
        while existingNames.contains(L("desk.defaultName", index)) {
            index += 1
        }
        return L("desk.defaultName", index)
    }

    // MARK: - Mutations

    /// Creates the first desk if there is none yet.
    func replaceActiveCalibration(forKey key: String, with profile: ProfileData) {
        var sets = loadSets()
        if var set = sets[key], let index = set.desks.firstIndex(where: { $0.id == set.activeDesk?.id }) {
            set.desks[index].profile = profile
            sets[key] = set
        } else {
            let desk = Desk(id: UUID().uuidString, name: L("desk.defaultName", 1), profile: profile)
            sets[key] = DeskSet(desks: [desk], activeDeskID: desk.id)
        }
        save(sets, mirroringKey: key)
    }

    @discardableResult
    func addDesk(named name: String, profile: ProfileData, forKey key: String) -> Desk {
        var sets = loadSets()
        var set = sets[key] ?? DeskSet(desks: [], activeDeskID: "")
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseName = trimmed.isEmpty ? nextDefaultName(forKey: key) : trimmed
        let desk = Desk(id: UUID().uuidString, name: uniqueName(for: baseName, in: set.desks), profile: profile)
        set.desks.append(desk)
        set.activeDeskID = desk.id
        sets[key] = set
        save(sets, mirroringKey: key)
        return desk
    }

    func selectDesk(id: String, forKey key: String) -> Desk? {
        var sets = loadSets()
        guard var set = sets[key], let desk = set.desks.first(where: { $0.id == id }) else { return nil }
        set.activeDeskID = id
        sets[key] = set
        save(sets, mirroringKey: key)
        return desk
    }

    @discardableResult
    func renameDesk(id: String, to name: String, forKey key: String) -> Bool {
        var sets = loadSets()
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              var set = sets[key],
              let index = set.desks.firstIndex(where: { $0.id == id }),
              !set.desks.contains(where: { $0.id != id && $0.name == trimmed }) else {
            return false
        }
        set.desks[index].name = trimmed
        sets[key] = set
        save(sets, mirroringKey: key)
        return true
    }

    @discardableResult
    func deleteDesk(id: String, forKey key: String) -> Bool {
        var sets = loadSets()
        guard var set = sets[key], set.desks.count > 1,
              let index = set.desks.firstIndex(where: { $0.id == id }) else {
            return false
        }
        set.desks.remove(at: index)
        if set.activeDeskID == id, let first = set.desks.first {
            set.activeDeskID = first.id
        }
        sets[key] = set
        save(sets, mirroringKey: key)
        return true
    }

    // MARK: - Persistence

    /// Only changed setups are re-encoded, so fields from newer builds survive.
    private var storedSets: [String: Data] = [:]

    /// Kept as-is until the user changes that setup.
    private var unreadableKeys: Set<String> = []

    /// The legacy `profiles` copy seeds setups without desks, and wins when an
    /// older build recalibrated after a downgrade.
    private func loadSets() -> [String: DeskSet] {
        var sets: [String: DeskSet] = [:]
        storedSets = userDefaults.dictionary(forKey: SettingsKeys.desks) as? [String: Data] ?? [:]
        unreadableKeys = []
        for (key, data) in storedSets {
            if let set = try? JSONDecoder().decode(DeskSet.self, from: data) {
                sets[key] = set
            } else {
                unreadableKeys.insert(key)
            }
        }

        let legacy = userDefaults.dictionary(forKey: SettingsKeys.profiles) as? [String: Data] ?? [:]
        var changedKeys: Set<String> = []
        for (key, data) in legacy {
            guard let profile = try? JSONDecoder().decode(ProfileData.self, from: data) else { continue }
            if var set = sets[key] {
                guard let index = set.desks.firstIndex(where: { $0.id == set.activeDesk?.id }),
                      set.desks[index].profile != profile else { continue }
                set.desks[index].profile = profile
                sets[key] = set
                changedKeys.insert(key)
            } else if unreadableKeys.contains(key) {
                // Not persisted, so the id must be stable
                let desk = Desk(id: "legacy", name: L("desk.defaultName", 1), profile: profile)
                sets[key] = DeskSet(desks: [desk], activeDeskID: desk.id)
            } else {
                let desk = Desk(id: UUID().uuidString, name: L("desk.defaultName", 1), profile: profile)
                sets[key] = DeskSet(desks: [desk], activeDeskID: desk.id)
                changedKeys.insert(key)
            }
        }
        if !changedKeys.isEmpty {
            write(sets, changedKeys: changedKeys)
        }
        return sets
    }

    private func save(_ sets: [String: DeskSet], mirroringKey key: String) {
        write(sets, changedKeys: [key])

        guard let profile = sets[key]?.activeDesk?.profile,
              let encoded = try? JSONEncoder().encode(profile) else { return }
        var legacy = userDefaults.dictionary(forKey: SettingsKeys.profiles) as? [String: Data] ?? [:]
        legacy[key] = encoded
        userDefaults.set(legacy, forKey: SettingsKeys.profiles)
    }

    private func write(_ sets: [String: DeskSet], changedKeys: Set<String>) {
        for key in changedKeys {
            guard let set = sets[key], let data = try? JSONEncoder().encode(set) else { continue }
            storedSets[key] = data
            unreadableKeys.remove(key)
        }
        userDefaults.set(storedSets, forKey: SettingsKeys.desks)
    }

    private func uniqueName(for name: String, in desks: [Desk]) -> String {
        let existingNames = Set(desks.map(\.name))
        guard existingNames.contains(name) else { return name }
        var index = 2
        while existingNames.contains("\(name) \(index)") {
            index += 1
        }
        return "\(name) \(index)"
    }
}
