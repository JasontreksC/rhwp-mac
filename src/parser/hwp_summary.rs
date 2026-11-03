//! HWP5/HWPX에서 읽는 저장 프로그램 메타데이터.
//!
//! HWP5는 `HwpSummaryInformation.revisionNumber`, HWPX는
//! `version.xml`의 `appVersion`을 사용한다. 둘 다 사용자가 지우거나 바꿀 수 있으므로
//! 문서의 원 작성 도구가 아니라 **마지막 저장 도구의 메타데이터**로만 취급한다.

use quick_xml::events::Event;
use quick_xml::Reader;

/// `HwpSummaryInformation`의 `PIDSI_REVNUMBER` 속성 ID.
const REVISION_NUMBER_PID: u32 = 0x0000_0009;
const VT_LPSTR: u32 = 0x001E;
const VT_LPWSTR: u32 = 0x001F;

fn local_name(name: &str) -> &[u8] {
    name.rsplit(':').next().unwrap_or(name).as_bytes()
}
