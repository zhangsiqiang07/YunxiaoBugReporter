Pod::Spec.new do |s|
  s.name             = 'YunxiaoBugReporter'
  s.version          = '0.1.0'
  s.summary          = 'Lightweight iOS SDK to report bugs (with screenshots & logs) to Alibaba Yunxiao (云效) Projex work items.'
  s.description      = <<-DESC
    YunxiaoBugReporter is a small, dependency-free iOS SDK (Swift 5.9, iOS 15+) that reports
    bugs to Alibaba Yunxiao (云效) Projex Bug work items. It queries the available Bug work
    item types, automatically selects a default type, creates the work item, and uploads image /
    text / log attachments as multipart/form-data. Networking is built on URLSession with
    async/await. No screenshot capture or crash reporting is included — the host app owns that
    part of the data collection.

    A ready-to-use SwiftUI UI is bundled in the SDK so a host app can embed the full Bug
    reporting flow with minimal code:
        let store = YXBConfigStore(domain: ..., organizationID: ..., defaultToken: ...)
        UIHostingController(rootView: YXBRootView().environmentObject(store))
    The bundled UI includes a Bug list (with pagination + project switching), a Bug detail view
    (with authenticated image rendering), a submit form (with member picker, required fields and
    photo attachments) and a configuration screen.

    Features:
    - Center (中心版) and Region (Region 版) API URL construction.
    - Async/await based, URLSession only (no Alamofire).
    - Injectable transport for fully mocked unit tests.
    - Token is fetched per-call via an async tokenProvider closure; the SDK never persists it.
    - Partial attachment failures return `partialSuccess` instead of throwing.
    - Bundled SwiftUI UI (`YXBRootView` + `YXBConfigStore`) for drop-in integration.
  DESC

  s.homepage         = 'https://github.com/your-org/YunxiaoBugReporter'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'Your Team' => 'your-email@example.com' }
  s.source           = { :git => 'https://github.com/your-org/YunxiaoBugReporter.git', :tag => s.version.to_s }

  s.ios.deployment_target = '15.0'
  s.swift_versions = ['5.9']

  s.source_files = 'Sources/**/*.swift'
  s.frameworks   = ['Foundation', 'SwiftUI', 'PhotosUI', 'UIKit']
  s.requires_arc = true

  # Unit tests are compiled (not executed) during `pod lib lint` to keep the pod honest.
  s.test_spec 'Tests' do |t|
    t.source_files = 'Tests/**/*.swift'
  end
end
