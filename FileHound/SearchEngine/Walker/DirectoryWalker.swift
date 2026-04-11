import Foundation

enum DirectoryWalkControl {
    case `continue`
    case stop
}

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
        var results: [DirectoryEntry] = []
        _ = try walk(plan: plan, includeHiddenFiles: includeHiddenFiles) { entry in
            results.append(entry)
            return .continue
        }
        return results
    }

    @discardableResult
    func walk(
        plan: SearchPlan,
        includeHiddenFiles: Bool,
        visit: (DirectoryEntry) throws -> DirectoryWalkControl
    ) throws -> Bool {
        let provider = providerFactory(plan.providerKind)
        for rootPath in plan.rootPaths {
            guard Task.isCancelled == false else {
                return false
            }

            let didFinish = try walkDirectory(
                atPath: rootPath,
                provider: provider,
                includeHiddenFiles: includeHiddenFiles,
                excludedPathFragments: plan.excludedPathFragments,
                specialFolderPlanning: plan.specialFolderPlanningResult,
                visit: visit
            )

            if didFinish == false {
                return false
            }
        }
        return true
    }

    private func walkDirectory(
        atPath path: String,
        provider: any FilesystemAccessProviding,
        includeHiddenFiles: Bool,
        excludedPathFragments: Set<String>,
        specialFolderPlanning: SpecialFolderPlanningResult,
        visit: (DirectoryEntry) throws -> DirectoryWalkControl
    ) throws -> Bool {
        let childNames: [String]

        do {
            childNames = try provider.contentsOfDirectory(atPath: path)
        } catch {
            return true
        }

        for childName in childNames {
            guard Task.isCancelled == false else {
                return false
            }
            let childPath = (path as NSString).appendingPathComponent(childName)

            guard excludedPathFragments.contains(where: childPath.contains) == false else {
                continue
            }

            guard specialFolderPlanning.allows(path: childPath) else {
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

            if try visit(entry) == .stop {
                return false
            }

            if isDirectory {
                let didFinish = try walkDirectory(
                    atPath: childPath,
                    provider: provider,
                    includeHiddenFiles: includeHiddenFiles,
                    excludedPathFragments: excludedPathFragments,
                    specialFolderPlanning: specialFolderPlanning,
                    visit: visit
                )
                if didFinish == false {
                    return false
                }
            }
        }

        return true
    }
}
