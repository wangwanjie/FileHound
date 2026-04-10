import Foundation

struct DirectoryEntry: Equatable, Sendable {
    let path: String
    let isDirectory: Bool
    let isHidden: Bool

    var lastPathComponent: String {
        URL(fileURLWithPath: path).lastPathComponent
    }
}

struct DirectoryWalker: Sendable {
    private let providerFactory: @Sendable (ProviderKind) -> any FilesystemAccessProviding

    init(
        providerFactory: @escaping @Sendable (ProviderKind) -> any FilesystemAccessProviding = { kind in
            switch kind {
            case .local:
                return LocalFilesystemProvider()
            case .privileged:
                return PrivilegedFilesystemProvider()
            }
        }
    ) {
        self.providerFactory = providerFactory
    }

    func walk(plan: SearchPlan, includeHiddenFiles: Bool) throws -> [DirectoryEntry] {
        let provider = providerFactory(plan.providerKind)
        return try plan.rootPaths.flatMap { rootPath in
            guard Task.isCancelled == false else {
                return [DirectoryEntry]()
            }
            return try walkDirectory(
                atPath: rootPath,
                provider: provider,
                includeHiddenFiles: includeHiddenFiles,
                excludedPathFragments: plan.excludedPathFragments
            )
        }
    }

    private func walkDirectory(
        atPath path: String,
        provider: any FilesystemAccessProviding,
        includeHiddenFiles: Bool,
        excludedPathFragments: Set<String>
    ) throws -> [DirectoryEntry] {
        var results: [DirectoryEntry] = []
        let childNames: [String]

        do {
            childNames = try provider.contentsOfDirectory(atPath: path)
        } catch {
            return []
        }

        for childName in childNames {
            guard Task.isCancelled == false else {
                break
            }
            let childPath = (path as NSString).appendingPathComponent(childName)

            guard excludedPathFragments.contains(where: childPath.contains) == false else {
                continue
            }

            let attributes: [FileAttributeKey: Any]
            do {
                attributes = try provider.attributesOfItem(atPath: childPath)
            } catch {
                continue
            }
            let isDirectory = attributes[.type] as? FileAttributeType == .typeDirectory
            let entry = DirectoryEntry(
                path: childPath,
                isDirectory: isDirectory,
                isHidden: childName.hasPrefix(".")
            )

            guard includeHiddenFiles || entry.isHidden == false else {
                continue
            }

            results.append(entry)

            if isDirectory {
                results.append(
                    contentsOf: try walkDirectory(
                        atPath: childPath,
                        provider: provider,
                        includeHiddenFiles: includeHiddenFiles,
                        excludedPathFragments: excludedPathFragments
                    )
                )
                continue
            }
        }

        return results
    }
}
