import UIKit
import SwiftUI
import YunxiaoBugReporter

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    /// 持有配置存储，避免被提前释放。
    let store = YXBConfigStore()

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // 薄壳宿主：使用默认初始化的 YXBConfigStore()，随后在代码中按需填充凭据
        // （SDK 不硬编码任何凭据，所有注入参数均有默认值）。
        store.domain = DemoConstants.domain
        store.organizationID = DemoConstants.organizationID
        store.token = DemoConstants.token
        store.defaultAssignedTo = DemoConstants.defaultAssignedTo

        // 示例宿主根界面：一个按钮，点击后 present「Bug 上报根界面」。
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = ExampleRootViewController(store: store)
        window.makeKeyAndVisible()
        self.window = window

        return true
    }
}

/// 示例宿主根界面（UIKit 实现，不放在 SDK 内）：
/// 仅放置一个「打开 Bug 上报」按钮，点击后以全屏 modal 的方式 present
/// `BugReporterRootViewController`；退出（dismiss）后回到本界面，可再次进入。
final class ExampleRootViewController: UIViewController {
    let store: YXBConfigStore

    private let openButton: UIButton = {
        let b = UIButton(type: .system)
        b.setTitle("打开 Bug 上报", for: .normal)
        b.setTitleColor(.white, for: .normal)
        b.titleLabel?.font = UIFont.systemFont(ofSize: 18, weight: .semibold)
        b.backgroundColor = UIColor.systemBlue
        b.layer.cornerRadius = 12
        b.contentEdgeInsets = UIEdgeInsets(top: 12, left: 28, bottom: 12, right: 28)
        return b
    }()

    init(store: YXBConfigStore) {
        self.store = store
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "示例宿主"
        view.backgroundColor = .systemBackground
        setupOpenButton()
    }

    private func setupOpenButton() {
        openButton.addTarget(self, action: #selector(openReporter), for: .touchUpInside)
        openButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(openButton)
        NSLayoutConstraint.activate([
            openButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            openButton.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    @objc private func openReporter() {
        let reporter = BugReporterRootViewController(store: store)
        reporter.modalPresentationStyle = .fullScreen
        present(reporter, animated: true, completion: nil)
    }
}

/// Example 侧的根界面（UIKit 实现，不放在 SDK 内）：
/// 以 `UITabBarController` 承载 SDK 内置的两个 SwiftUI 页面（Bug 列表 / 云效配置），
/// 「退出」按钮放在各页面自身的导航栏右侧（由 SDK 视图通过 onExit 回调触发），
/// 列表底部、TabBar 之上另叠加一个「添加Bug」悬浮按钮：仅 Bug 列表 Tab 显示，
/// 点击以全屏 modal 进入 `SubmitView`（含「关闭」按钮）。
final class BugReporterRootViewController: UIViewController {
    let store: YXBConfigStore

    private var mainTabBarController: UITabBarController!

    // MARK: - 悬浮按钮

    private let addBugButton: UIButton = {
        let b = UIButton(type: .system)
        b.setTitle("+ 添加Bug", for: .normal)
        b.setTitleColor(.white, for: .normal)
        b.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
        b.backgroundColor = UIColor.systemBlue
        b.layer.cornerRadius = 24
        b.layer.shadowColor = UIColor.black.cgColor
        b.layer.shadowOpacity = 0.22
        b.layer.shadowRadius = 6
        b.layer.shadowOffset = CGSize(width: 0, height: 3)
        return b
    }()

    init(store: YXBConfigStore) {
        self.store = store
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        // 1) 构建 TabBar：两个 Tab 分别承载 SDK 内置的 SwiftUI 页面。
        let tabBarController = UITabBarController()
        self.mainTabBarController = tabBarController
        tabBarController.delegate = self

        // 退出回调：优先关掉可能叠着的「提交 Bug」modal，再 dismiss 整个全屏根界面。
        let onExit: () -> Void = { [weak self] in
            guard let self else { return }
            if let presented = self.presentedViewController {
                presented.dismiss(animated: false) { [weak self] in
                    self?.dismiss(animated: true)
                }
            } else {
                self.dismiss(animated: true)
            }
        }

        let bugListVC = UIHostingController(
            rootView: NavigationView { BugListView(onExit: onExit) }
                .navigationViewStyle(.stack)
                .environmentObject(store)
        )
        bugListVC.tabBarItem = UITabBarItem(
            title: "Bug 列表",
            image: UIImage(systemName: "list.bullet"),
            selectedImage: nil
        )

        let configVC = UIHostingController(
            rootView: NavigationView { ConfigView(mode: .normal, onExit: onExit) }
                .navigationViewStyle(.stack)
                .environmentObject(store)
        )
        configVC.tabBarItem = UITabBarItem(
            title: "云效配置",
            image: UIImage(systemName: "gearshape.fill"),
            selectedImage: nil
        )

        tabBarController.viewControllers = [bugListVC, configVC]
        // 尚未配置云效信息时，默认停在「云效配置」Tab，引导先完成配置。
        tabBarController.selectedIndex = store.isConfigured ? 0 : 1

        addChild(tabBarController)
        view.addSubview(tabBarController.view)
        tabBarController.didMove(toParent: self)

        // 2) 叠加悬浮按钮：仅保留列表底部「添加Bug」。
        setupAddBugButton()
        updateAddBugButtonVisibility()
    }

    // MARK: - 悬浮按钮布局

    private func setupAddBugButton() {
        addBugButton.addTarget(self, action: #selector(addBugTapped), for: .touchUpInside)
        addBugButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(addBugButton)
        view.bringSubviewToFront(addBugButton)
        NSLayoutConstraint.activate([
            // 悬浮在 TabBar 之上（距 TabBar 顶边 12pt），水平居中。
            addBugButton.bottomAnchor.constraint(equalTo: mainTabBarController.tabBar.topAnchor, constant: -12),
            addBugButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            addBugButton.heightAnchor.constraint(equalToConstant: 48),
            addBugButton.widthAnchor.constraint(equalToConstant: 150)
        ])
    }

    /// 「添加Bug」仅当停留在 Bug 列表 Tab 时显示。
    private func updateAddBugButtonVisibility() {
        addBugButton.isHidden = (mainTabBarController.selectedIndex != 0)
    }

    // MARK: - 交互

    @objc private func addBugTapped() {
        let submitHosting = UIHostingController(
            rootView: SubmitView().environmentObject(store)
        )
        // SubmitView 自身无关闭按钮（原依赖导航返回），此处补一个「关闭」以 modal 形式退出。
        submitHosting.navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "关闭",
            style: .done,
            target: self,
            action: #selector(dismissPresented)
        )
        let nav = UINavigationController(rootViewController: submitHosting)
        nav.modalPresentationStyle = .fullScreen
        present(nav, animated: true, completion: nil)
    }

    @objc private func dismissPresented() {
        dismiss(animated: true, completion: nil)
    }
}

extension BugReporterRootViewController: UITabBarControllerDelegate {
    func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
        updateAddBugButtonVisibility()
    }
}
