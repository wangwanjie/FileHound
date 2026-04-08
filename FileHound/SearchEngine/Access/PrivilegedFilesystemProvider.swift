struct PrivilegedFilesystemProvider: FilesystemAccessProviding, Sendable {
    let kind: ProviderKind = .privileged

    init() {}
}
