import SwiftUI

/// Example 入口：先是一个「进入」落地页（单一入口）；进入后若尚未配置云效信息，
/// 强制先到配置页；否则进入主界面（Tab：Bug 列表 / 云效配置）。
struct ContentRoot: View {
    @EnvironmentObject private var store: DemoConfigStore
    @State private var entered = false
    @State private var showMain = false

    var body: some View {
        Group {
            if !entered {
                LandingView(onEnter: { entered = true })
            } else if store.isConfigured || showMain {
                MainTabView()
            } else {
                NavigationStack {
                    ConfigView(mode: .forced, onComplete: { showMain = true })
                }
            }
        }
    }
}

/// 单一进入页：点击「进入」即进入 SDK 演示。若信息未配置，下一屏强制为配置页。
struct LandingView: View {
    let onEnter: () -> Void

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(.systemBackground), Color(.secondarySystemBackground)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 28) {
                Image(systemName: "ant.circle.fill")
                    .font(.system(size: 76))
                    .foregroundStyle(.tint)
                    .symbolRenderingMode(.hierarchical)

                VStack(spacing: 8) {
                    Text("YunxiaoBugReporter")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                    Text("云效 Projex · Bug 上报演示")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Button(action: onEnter) {
                    Text("进入")
                        .font(.headline)
                        .frame(width: 200)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.accentColor)
            }
        }
    }
}

/// 主界面：两个 Tab —— 当前项目的 Bug 列表（含提交入口）与 云效配置。
///
/// - Tab1「Bug 列表」：`BugListView` 负责展示当前项目的 Bug、分页加载、左上角切换项目、
///   右上角「提交 Bug」按钮推入 `SubmitView`；提交不再作为独立 Tab。
/// - Tab2「云效配置」：只读展示域名/组织ID/Token 并维护可变配置。
struct MainTabView: View {
    var body: some View {
        TabView {
            NavigationStack { BugListView() }
                .tabItem { Label("Bug 列表", systemImage: "list.bullet") }

            NavigationStack { ConfigView(mode: .normal) }
                .tabItem { Label("云效配置", systemImage: "gearshape.fill") }
        }
    }
}
