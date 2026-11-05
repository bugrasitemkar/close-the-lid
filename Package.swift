// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "CloseTheLid",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "CloseTheLid",
            path: "Sources/CloseTheLid",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("IOKit"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("UserNotifications"),
            ]
        )
    ]
)
