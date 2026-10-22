import Foundation

/// 一次目录遍历的计划：从哪些根目录开始，以及每个根目录各自的特殊文件夹规划
struct SearchPlan: Equatable, Sendable {
    let rootPaths: [String]
    /// 与 rootPaths 一一对应。每个根目录只使用自己的规划，避免某个根的排除规则串到其他根上
    let specialFolderPlanning: [SpecialFolderPlanningResult]

    init(rootPaths: [String], specialFolderPlanning: [SpecialFolderPlanningResult]) {
        precondition(specialFolderPlanning.count == rootPaths.count, "每个搜索根都需要一份特殊文件夹规划")
        self.rootPaths = rootPaths
        self.specialFolderPlanning = specialFolderPlanning
    }

    /// 所有根目录共用同一份规划（默认不做任何特殊文件夹处理）
    init(rootPaths: [String], sharedPlanning: SpecialFolderPlanningResult = SpecialFolderPlanningResult()) {
        self.init(rootPaths: rootPaths, specialFolderPlanning: rootPaths.map { _ in sharedPlanning })
    }
}
