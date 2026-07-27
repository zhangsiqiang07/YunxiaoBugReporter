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
        // 薄壳宿主：凭据由 DemoConstants 提供，注入 SDK 内置的通用配置存储，
        // 再用 SDK 开箱即用的根视图 YXBRootView 承载完整 Bug 上报界面。
        let store = YXBConfigStore(
            domain: DemoConstants.domain,
            organizationID: DemoConstants.organizationID,
            defaultToken: DemoConstants.token
        )
        let window = UIWindow(frame: UIScreen.main.bounds)
        let root = UIHostingController(rootView: YXBRootView().environmentObject(store))
        root.view.backgroundColor = .systemBackground
        window.rootViewController = root
        window.makeKeyAndVisible()
        self.window = window
        return true
    }
}
