import RhwpViewer
import Testing

@Suite("Zoom")
struct ZoomTests {
    @Test("확대는 다음 단계로, 축소는 이전 단계로 움직인다")
    func stepsMoveOneAtATime() {
        #expect(Zoom(1.0).zoomedIn().factor == 1.25)
        #expect(Zoom(1.0).zoomedOut().factor == 0.75)
        #expect(Zoom(0.25).zoomedIn().factor == 0.5)
        #expect(Zoom(4.0).zoomedOut().factor == 3.0)
    }

    @Test("단계에 없는 배율(맞춤 배율)에서도 한 번 누르면 달라진다")
    func offGridZoomStillMoves() {
        let fit = Zoom(0.87)
        #expect(fit.zoomedIn().factor == 1.0)
        #expect(fit.zoomedOut().factor == 0.75)
        // 부동소수 오차가 있는 단계 값에서도 같은 단계를 다시 고르지 않는다.
        #expect(Zoom(1.0 + 1e-12).zoomedIn().factor == 1.25)
        #expect(Zoom(1.25 - 1e-12).zoomedOut().factor == 1.0)
    }

    @Test("끝에서는 더 움직이지 않고 가능 여부가 거짓이 된다")
    func endsAreSticky() {
        #expect(Zoom(4.0).zoomedIn().factor == 4.0 && !Zoom(4.0).canZoomIn && Zoom(4.0).canZoomOut)
        #expect(Zoom(0.25).zoomedOut().factor == 0.25 && !Zoom(0.25).canZoomOut && Zoom(0.25).canZoomIn)
    }

    @Test("범위 밖과 비정상 값은 맞춰 둔다", arguments: [
        (10.0, 4.0), (0.0, 0.25), (-3.0, 0.25), (Double.infinity, 1.0), (Double.nan, 1.0), (1.5, 1.5),
    ])
    func clamping(input: Double, expected: Double) {
        #expect(Zoom(input).factor == expected)
    }

    @Test("퍼센트 표시는 반올림한다")
    func percentLabel() {
        #expect(Zoom(1.25).percentLabel == "125%")
        #expect(Zoom(0.87).percentLabel == "87%")
        #expect(Zoom(0.333).percentLabel == "33%")
    }

    @Test("너비 맞춤은 사용 가능한 너비 ÷ 쪽 너비다")
    func fitWidth() {
        // A4 793.7px 쪽을 800pt 영역에 맞추면 800/793.7.
        #expect(abs(Zoom.fitWidth(availableWidth: 800, pageWidth: 793.7).factor - 800 / 793.7) < 1e-12)
        #expect(Zoom.fitWidth(availableWidth: 100_000, pageWidth: 800).factor == 4.0, "범위 상한으로 맞춤")
        #expect(Zoom.fitWidth(availableWidth: 0, pageWidth: 800) == .actualSize, "영역이 없으면 100%")
        #expect(Zoom.fitWidth(availableWidth: 800, pageWidth: 0) == .actualSize)
    }

    @Test("쪽 맞춤은 너비·높이 중 더 빡빡한 쪽에 맞춘다")
    func fitPage() {
        let tall = Zoom.fitPage(availableWidth: 1000, availableHeight: 500, pageWidth: 800, pageHeight: 1000)
        #expect(abs(tall.factor - 0.5) < 1e-12, "높이가 더 빡빡하다")
        let wide = Zoom.fitPage(availableWidth: 400, availableHeight: 5000, pageWidth: 800, pageHeight: 1000)
        #expect(abs(wide.factor - 0.5) < 1e-12, "너비가 더 빡빡하다")
    }
}
