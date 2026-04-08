struct MetadataEvaluator: Sendable {
    func matchesName(_ entry: DirectoryEntry, fragment: String) -> Bool {
        entry.lastPathComponent.localizedCaseInsensitiveContains(fragment)
    }

    func matchesPath(_ entry: DirectoryEntry, fragment: String) -> Bool {
        entry.path.localizedCaseInsensitiveContains(fragment)
    }
}
