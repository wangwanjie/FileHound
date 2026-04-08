import AppKit

final class SearchRulesViewController: NSViewController {
    override func loadView() {
        let container = NSView()

        let titleLabel = NSTextField(labelWithString: "搜索规则")
        titleLabel.font = .systemFont(ofSize: 18, weight: .semibold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let rowView = SearchRuleRowView(text: "名称包含 report")
        rowView.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(titleLabel)
        container.addSubview(rowView)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            titleLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 20),

            rowView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            rowView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            rowView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 12),
            rowView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -16)
        ])

        view = container
    }
}
