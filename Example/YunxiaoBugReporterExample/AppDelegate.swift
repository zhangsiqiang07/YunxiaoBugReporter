import UIKit
import SwiftUI
import YunxiaoBugReporter

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // 薄壳宿主：使用默认初始化的 YXBConfigStore()，随后在代码中按需填充凭据
        // （SDK 不硬编码任何凭据，所有注入参数均有默认值）。
        let store = YXBConfigStore()
        store.domain = DemoConstants.domain
        store.organizationID = DemoConstants.organizationID
        store.token = DemoConstants.token
        // 可选：注入默认负责人（云效用户 ID），未显式选择负责人时自动回退使用该值。
        // store.defaultAssignedTo = "<云效用户 ID>"
        let window = UIWindow(frame: UIScreen.main.bounds)
        let root = UIHostingController(rootView: YXBRootView().environmentObject(store))
        root.view.backgroundColor = .systemBackground
        window.rootViewController = root
        window.makeKeyAndVisible()
        self.window = window
        return true
    }
}
