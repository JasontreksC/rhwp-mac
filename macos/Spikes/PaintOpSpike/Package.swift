// swift-tools-version: 6.2

import PackageDescription

// 0단계 스파이크: Rust 레이어 트리(PaintOp IR)를 CoreGraphics/CoreText로 재생할 수 있는지 검증한다.
// 제품 코드가 아니며, 2~4단계에서 RhwpKit/렌더러로 대체된다.
//
// Rust FFI는 1단계 산출물인 정적 XCFramework를 binaryTarget으로 소비한다.
// 먼저 macos/scripts/build-xcframework.sh 로 만들어야 하며, build-and-run.sh 가 이를 대신 실행한다.
let package = Package(
    name: "PaintOpSpike",
    platforms: [.macOS(.v26)],
    targets: [
        .binaryTarget(
            name: "CRhwp",
            path: "../../build/RhwpNative.xcframework"
        ),
        .executableTarget(
            name: "paintop-spike",
            dependencies: ["CRhwp"]
        ),
    ]
)
