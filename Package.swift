// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CPAMPMonitor",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "CPAMPMonitor", targets: ["CPAMPMonitor"])],
    targets: [
        .target(name: "MonitorCore"),
        .executableTarget(name: "CPAMPMonitor", dependencies: ["MonitorCore"]),
        .executableTarget(name: "MonitorChecks", dependencies: ["MonitorCore"], path: "Tests/MonitorCoreTests")
    ]
)
