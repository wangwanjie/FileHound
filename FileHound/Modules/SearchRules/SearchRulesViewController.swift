import AppKit
import SnapKit

final class SearchRulesViewController: NSViewController {
    override func loadView() {
        let container = NSView()

        let titleLabel = NSTextField(labelWithString: L10n.string("search_rules.title"))
        titleLabel.font = .systemFont(ofSize: 18, weight: .semibold)

        let rowView = SearchRuleRowView(text: L10n.string("search_rules.sample"))

        container.addSubview(titleLabel)
        container.addSubview(rowView)

        titleLabel.snp.makeConstraints { make in
            make.leading.top.equalToSuperview().inset(20)
        }
        rowView.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(20)
            make.top.equalTo(titleLabel.snp.bottom).offset(12)
            make.bottom.equalToSuperview().inset(16)
        }

        view = container
    }
}
