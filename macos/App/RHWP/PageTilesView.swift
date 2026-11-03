import CoreGraphics
import RhwpRender
import RhwpViewer
import SwiftUI

/// 쪽 하나. 흰 종이 위에 흐린 쪽 전체 밑그림과 타일들이 겹쳐 놓인다.
///
/// 크기는 호출자가 정한다(쪽 배치가 그림보다 먼저 정해지므로 그림이 늦어도 스크롤 길이가 흔들리지 않는다). 그릴 타일은
/// `ViewerModel.renderPlan`이 정한다: 지금 보이는 곳(과 조금 바깥)의 타일만 그리고, 새 타일이 오기 전에는 캐시에 남은 이전
/// 배율의 타일과 쪽 전체 밑그림이 대신 보인다.
///
/// **타일마다 `Image` 뷰를 쓰고 `Canvas` 한 장에 그리지 않는 이유**: `Canvas`는 자기 크기만큼의 백킹 스토어를 잡는다.
/// 확대 4배 Retina의 쪽 하나는 6350×8980px(228MB)라 타일로 나눈 이득이 사라진다. `Image`는 `CGImage`가 그대로 레이어
/// 내용이 되어 타일 하나(1MB)만큼만 든다.
struct PageTilesView: View {
    let model: ViewerModel
    let page: Int
    let size: CGSize

    @Environment(\.displayScale) private var displayScale

    /// 타일 요청 작업의 키. 아직 없는 타일이 바뀔 때만(도착했거나 보이는 영역이 움직였을 때) 새로 시작한다.
    private struct LoadKey: Hashable {
        var scaleMilli: Int
        var missing: [TileIndex]
    }

    var body: some View {
        // 본문에서 읽으므로 보이는 영역·확대·새 타일 도착(tileRevision)이 바뀌면 다시 계산된다.
        let plan = model.renderPlan(page: page, displayScale: displayScale)
        ZStack(alignment: .topLeading) {
            Rectangle().fill(.white)
            if let cover = plan?.cover {
                Image(decorative: cover, scale: 1, orientation: .up)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: size.width, height: size.height)
            }
            if let plan {
                ForEach(plan.items) { item in
                    Image(decorative: item.image, scale: 1, orientation: .up)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: item.frame.width, height: item.frame.height)
                        .offset(x: item.frame.minX, y: item.frame.minY)
                }
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .clipped()
        .task(id: LoadKey(scaleMilli: Int(((plan?.tiles.scale ?? 0) * 1000).rounded()), missing: plan?.missing ?? []), priority: .userInitiated) {
            guard let plan, !plan.missing.isEmpty else { return }
            // 화면에서 사라지거나 다음 키로 넘어가면 이 작업이 취소되고, 아직 시작하지 않은 타일은 그려지지 않는다.
            await model.loadTiles(page: page, scale: plan.tiles.scale, indices: plan.missing)
        }
        .task(id: page, priority: .utility) {
            await model.loadCover(page: page)
        }
        .accessibilityElement()
        .accessibilityLabel("\(page + 1)쪽")
    }
}
