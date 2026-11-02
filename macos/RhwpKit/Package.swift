// swift-tools-version: 6.2

import PackageDescription

// RhwpKit: Rust 문서 엔진(bindings/Native)을 Swift 6 동시성 모델로 감싼 패키지.
//
// 네이티브 계층은 1단계 산출물인 정적 XCFramework(모듈 CRhwp)다.
// `swift build`/`swift test` 전에 macos/scripts/build-xcframework.sh 로 만들어야 하며,
// macos/scripts/test-rhwpkit.sh 가 이를 대신 실행한다.
let package = Package(
    name: "RhwpKit",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "RhwpKit", targets: ["RhwpKit"]),
    ],
    targets: [
        .binaryTarget(
            name: "CRhwp",
            path: "../build/RhwpNative.xcframework"
        ),
        .target(
            name: "RhwpKit",
            dependencies: ["CRhwp"]
        ),
        .testTarget(
            name: "RhwpKitTests",
            dependencies: ["RhwpKit"]
        ),
    ]
)
