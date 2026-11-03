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
        .library(name: "RhwpRender", targets: ["RhwpRender"]),
        .library(name: "RhwpViewer", targets: ["RhwpViewer"]),
        .executable(name: "rhwp-render", targets: ["rhwp-render"]),
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
        // 레이어 트리(PaintOp IR)를 CoreGraphics/CoreText로 그리는 렌더러. 엔진 호출은 하지 않고 모델만 소비한다.
        .target(
            name: "RhwpRender",
            dependencies: ["RhwpKit"]
        ),
        // 뷰어 로직(확대·축소 단계, 쪽 배치). UI 프레임워크에 의존하지 않아 단위 시험이 가능하다.
        .target(
            name: "RhwpViewer",
            dependencies: ["RhwpKit"]
        ),
        // 문서의 한 쪽을 PNG로 그리는 명령줄 도구(시각 검증의 입력을 만든다).
        .executableTarget(
            name: "rhwp-render",
            dependencies: ["RhwpKit", "RhwpRender"]
        ),
        .testTarget(
            name: "RhwpKitTests",
            dependencies: ["RhwpKit"]
        ),
        .testTarget(
            name: "RhwpRenderTests",
            dependencies: ["RhwpKit", "RhwpRender"]
        ),
        .testTarget(
            name: "RhwpViewerTests",
            dependencies: ["RhwpKit", "RhwpViewer"]
        ),
    ]
)
