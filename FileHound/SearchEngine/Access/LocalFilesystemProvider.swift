struct LocalFilesystemProvider: FilesystemAccessProviding, Sendable {
    let kind: ProviderKind = .local

    init() {}
}
