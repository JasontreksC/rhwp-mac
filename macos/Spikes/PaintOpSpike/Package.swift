// swift-tools-version: 6.2

import PackageDescription

// 0단계 스파이크: Rust 레이어 트리(PaintOp IR)를 CoreGraphics/CoreText로 재생할 수 있는지 검증한다.
// 제품 코드가 아니며, 1~4단계에서 RhwpKit/렌더러로 대체된다.
//
// 정적 라이브러리 위치는 빌드 스크립트(build-and-run.sh)가 `-Xlinker -L`로 넘긴다.
let package = Package(
    name: "PaintOpSpike",
    platforms: [.macOS(.v26)],
    targets: [
        .systemLibrary(
            name: "CRhwpSpike",
            path: "Sources/CRhwpSpike"
        ),
        .executableTarget(
            name: "paintop-spike",
            dependencies: ["CRhwpSpike"]
        ),
    ]
)
