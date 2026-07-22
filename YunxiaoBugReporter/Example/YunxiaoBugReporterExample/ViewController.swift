import UIKit
import PhotosUI
import YunxiaoBugReporter

/// 最小演示页面：仅用于演示 SDK 调用，不属于 SDK Source。
///
/// 该页面：
/// - 输入 Bug 标题 / 描述；
/// - 从系统相册选择一张图片作为附件；
/// - 点击提交，将 Bug 上报到云效；
/// - 展示加载状态与提交结果。
///
/// ⚠️ 配置使用占位符，请勿在此写入真实 Token。Token 通过环境变量 `YUNXIAO_TOKEN` 注入。
final class ViewController: UIViewController {
    private let reporter = YunxiaoBugReporter()

    private let titleField: UITextField = {
        let field = UITextField()
        field.borderStyle = .roundedRect
        field.placeholder = "Bug 标题"
        field.translatesAutoresizingMaskIntoConstraints = false
        return field
    }()

    private let descriptionView: UITextView = {
        let view = UITextView()
        view.layer.borderColor = UIColor.systemGray4.cgColor
        view.layer.borderWidth = 1
        view.layer.cornerRadius = 8
        view.font = .systemFont(ofSize: 14)
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let pickButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("从相册选择一张图片", for: .normal)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private let submitButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("提交 Bug", for: .normal)
        button.backgroundColor = .systemBlue
        button.setTitleColor(.white, for: .normal)
        button.layer.cornerRadius = 8
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private let activityIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.hidesWhenStopped = true
        return indicator
    }()

    private let resultLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 0
        label.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        label.text = "尚未提交"
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private var selectedImageData: Data?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "YunxiaoBugReporter Demo"
        view.backgroundColor = .systemBackground
        setupUI()
        configureReporter()
    }

    // MARK: - 配置（占位符，绝不写入真实 Token）

    private func configureReporter() {
        // 占位符：请替换为你的真实云效参数。
        let organizationID = "<YOUR_ORGANIZATION_ID>"
        let projectID = "<YOUR_PROJECT_ID>"
        let assignedTo = "<YOUR_ASSIGNEE_USER_ID>"
        // Token 从环境变量读取，避免硬编码进仓库。
        let token = ProcessInfo.processInfo.environment["YUNXIAO_TOKEN"] ?? ""

        let config = YXBConfiguration(
            domain: "https://your-yunxiao-domain.com",
            edition: .standard,
            organizationID: organizationID,
            projectID: projectID,
            assignedTo: assignedTo,
            tokenProvider: { token }
        )
        do {
            try reporter.configure(config)
        } catch {
            showResult("配置失败: \(error.localizedDescription)")
        }
    }

    // MARK: - UI

    private func setupUI() {
        let stack = UIStackView(arrangedSubviews: [
            titleField, descriptionView, pickButton, submitButton, activityIndicator, resultLabel
        ])
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            descriptionView.heightAnchor.constraint(equalToConstant: 120)
        ])

        pickButton.addTarget(self, action: #selector(pickTapped), for: .touchUpInside)
        submitButton.addTarget(self, action: #selector(submitTapped), for: .touchUpInside)
    }

    // MARK: - 交互

    @objc private func pickTapped() {
        var config = PHPickerConfiguration()
        config.selectionLimit = 1
        config.filter = .images
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = self
        present(picker, animated: true)
    }

    @objc private func submitTapped() {
        let title = titleField.text ?? ""
        let description = descriptionView.text ?? ""
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            showResult("请填写 Bug 标题")
            return
        }

        var attachments: [YXBAttachment] = []
        if let data = selectedImageData {
            attachments.append(YXBAttachment(data: data, fileName: "screenshot.png", mimeType: "image/png"))
        }

        let report = YXBBugReport(title: title, description: description, attachments: attachments)

        setLoading(true)
        Task {
            do {
                let result = try await reporter.submit(report)
                let statusText = result.status == .success ? "success" : "partialSuccess"
                let summary = """
                提交完成
                workitemID: \(result.workitemID)
                status: \(statusText)
                成功附件: \(result.successfulAttachments.count)
                失败附件: \(result.failedAttachments.count)
                """
                await MainActor.run { self.setLoading(false); self.showResult(summary) }
            } catch {
                await MainActor.run { self.setLoading(false); self.showResult("提交失败: \(error.localizedDescription)") }
            }
        }
    }

    private func showResult(_ text: String) {
        resultLabel.text = text
    }

    private func setLoading(_ loading: Bool) {
        if loading { activityIndicator.startAnimating() } else { activityIndicator.stopAnimating() }
        submitButton.isEnabled = !loading
    }
}

extension ViewController: PHPickerViewControllerDelegate {
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let item = results.first else { return }
        item.itemProvider.loadObject(ofClass: UIImage.self) { [weak self] object, _ in
            guard let image = object as? UIImage, let data = image.pngData() else { return }
            DispatchQueue.main.async {
                self?.selectedImageData = data
                self?.pickButton.setTitle("已选择图片 (\(data.count) bytes)", for: .normal)
            }
        }
    }
}
