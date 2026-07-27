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

        // 不替换 window.rootViewController，而是用一个占位根控制器，
        // 再把「Bug 上报根界面」以全屏 modal 的方式 present 出来。
        let placeholder = UIViewController()
        placeholder.view.backgroundColor = .systemBackground

        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = placeholder
        window.makeKeyAndVisible()
        self.window = window

        let reporter = BugReporterRootViewController(store: store)
        reporter.modalPresentationStyle = .fullScreen
        placeholder.present(reporter, animated: false)

        return true
    }
}

/// Example 侧的根界面（UIKit 实现，不放在 SDK 内）：
/// 以 `UITabBarController` 承载 SDK 内置的两个 SwiftUI 页面（Bug 列表 / 云效配置），
/// 底部额外提供一个「退出」按钮，点击直接 dismiss 当前全屏界面，回到占位根控制器。
final class BugReporterRootViewController: UIViewController {
    let store: YXBConfigStore

    init(store: YXBConfigStore) {
        self.store = store
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private var mainTabBarController: UITabBarController!

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        // 1) 构建 TabBar：两个 Tab 分别承载 SDK 内置的 SwiftUI 页面。
        let tabBarController = UITabBarController()
        self.mainTabBarController = tabBarController

        let bugListVC = UIHostingController(
            rootView: NavigationView { BugListView() }
                .navigationViewStyle(.stack)
                .environmentObject(store)
        )
        bugListVC.tabBarItem = UITabBarItem(
            title: "Bug 列表",
            image: UIImage(systemName: "list.bullet"),
            selectedImage: nil
        )

        let configVC = UIHostingController(
            rootView: NavigationView { ConfigView(mode: .normal) }
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

        // 2) 作为子控制器加入，并约束其区域（底部留出「退出」栏的高度）。
        addChild(tabBarController)
        view.addSubview(tabBarController.view)
        tabBarController.didMove(toParent: self)

        // 3) 底部「退出」栏：点击直接退出当前全屏界面。
        let exitBar = UIView()
        exitBar.backgroundColor = .secondarySystemBackground
        exitBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(exitBar)

        let exitButton = UIButton(type: .system)
        exitButton.setTitle("退出", for: .normal)
        exitButton.titleLabel?.font = UIFont.systemFont(ofSize: 17, weight: .medium)
        exitButton.addTarget(self, action: #selector(exitTapped), for: .touchUpInside)
        exitButton.translatesAutoresizingMaskIntoConstraints = false
        exitBar.addSubview(exitButton)

        let exitBarHeight: CGFloat = 56
        NSLayoutConstraint.activate([
            // TabBar 区域
            tabBarController.view.topAnchor.constraint(equalTo: view.topAnchor),
            tabBarController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tabBarController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tabBarController.view.bottomAnchor.constraint(equalTo: exitBar.topAnchor),

            // 退出栏（底部，位于安全区之内，避免与 Home Indicator 重叠）
            exitBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            exitBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            exitBar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            exitBar.heightAnchor.constraint(equalToConstant: exitBarHeight),

            // 退出按钮居中
            exitButton.centerXAnchor.constraint(equalTo: exitBar.centerXAnchor),
            exitButton.centerYAnchor.constraint(equalTo: exitBar.centerYAnchor)
        ])
    }

    @objc private func exitTapped() {
        dismiss(animated: true, completion: nil)
    }
}
