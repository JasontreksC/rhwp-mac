//! [#2792] 표 안의 표(중첩 표) 텍스트가 검색에 잡히지 않던 결함.
//!
//! 검색 순회는 본문 문단의 컨트롤에서 `Control::Table` 로 들어가 셀 문단까지 훑었지만,
//! **셀 문단 안의 컨트롤**을 훑는 자리는 `Control::Equation` 만 봤다. 그래서 셀 안에
//! 들어 있는 표(중첩 표)는 어느 갈래에도 걸리지 않고 조용히 버려졌고, 그 안의 텍스트는
//! 순회 대상이 된 적이 없었다.
//!
//! 실패 모습이 나쁜 이유는 **오류가 아니기 때문**이다. 검색은 성공 응답에
//! 빈 결과를 돌려주므로 호출자는 "문서에 그 말이 없다"로 읽는다.
//! 규제심사·검토보고 양식처럼 바깥 표 한 칸 안에 본문 표를 넣는 구조에서는 본문
//! 상당 부분이 통째로 검색에서 빠진다.
//!
//! 이 파일이 못 박는 계약. (이 포크는 `grep` 질의를 제거했으므로, 같은 순회를 쓰는
//! `search_all_text_native` 와 `replace_all_native` 로 검증한다. `grep` 봉투에만 있던
//! `nestedDepth`·`page`·`limit` 계약은 기능과 함께 사라졌다.)
//!
//! 1. 중첩 표 안 텍스트가 **찾힌다** — 2단계 아래까지.
//! 2. 글상자 안 표의 텍스트도 찾힌다.
//! 3. `replace_all_native` 는 중첩 전용 토큰도 같은 검색 순회로 찾아 바꾼다.

use rhwp::document_core::DocumentCore;

/// 문서 전체(본문·표 셀·글상자·중첩 표)에서 `needle` 의 일치 개수를 센다.
fn hit_count(doc: &DocumentCore, needle: &str) -> usize {
    let json = doc
        .search_all_text_native(needle, true, true)
        .expect("검색은 실패하지 않아야 한다");
    serde_json::from_str::<serde_json::Value>(&json)
        .unwrap_or_else(|e| panic!("{e}: {json}"))
        .as_array()
        .expect("검색 결과는 JSON 배열이다")
        .len()
}

/// 3중 구조: 본문 → 바깥 표 셀 → 중첩 표 셀 → 더 깊은 표 셀.
/// 단어를 층마다 다르게 두어야 "어느 층까지 닿았는가"가 구별된다.
const NESTED_HML: &str = r#"<HWPML Version="2.91"><HEAD/><BODY><SECTION>
  <P><TEXT><CHAR>본문전용단어</CHAR></TEXT></P>
  <P><TEXT><TABLE RowCount="1" ColCount="1">
    <SHAPEOBJECT><SIZE Width="8000" Height="4000"/></SHAPEOBJECT>
    <ROW><CELL ColAddr="0" RowAddr="0" Width="8000" Height="4000"><PARALIST>
      <P><TEXT><CHAR>바깥셀단어</CHAR></TEXT></P>
      <P><TEXT><TABLE RowCount="1" ColCount="1">
        <SHAPEOBJECT><SIZE Width="6000" Height="3000"/></SHAPEOBJECT>
        <ROW><CELL ColAddr="0" RowAddr="0" Width="6000" Height="3000"><PARALIST>
          <P><TEXT><CHAR>중첩셀단어</CHAR></TEXT></P>
          <P><TEXT><TABLE RowCount="1" ColCount="1">
            <SHAPEOBJECT><SIZE Width="4000" Height="2000"/></SHAPEOBJECT>
            <ROW><CELL ColAddr="0" RowAddr="0" Width="4000" Height="2000"><PARALIST>
              <P><TEXT><CHAR>더깊은셀단어</CHAR></TEXT></P>
            </PARALIST></CELL></ROW>
          </TABLE></TEXT></P>
        </PARALIST></CELL></ROW>
      </TABLE></TEXT></P>
    </PARALIST></CELL></ROW>
  </TABLE></TEXT></P>
</SECTION></BODY><TAIL/></HWPML>"#;

const TEXTBOX_TABLE_HML: &str = r#"<HWPML Version="2.91"><HEAD/><BODY><SECTION>
  <P><TEXT><RECTANGLE X0="0" X1="5000" X2="5000" X3="0" Y0="0" Y1="0" Y2="2400" Y3="2400">
    <SHAPEOBJECT><SIZE Width="5000" Height="2400"/></SHAPEOBJECT>
    <DRAWINGOBJECT><SHAPECOMPONENT XPos="0" YPos="0" OriWidth="5000" OriHeight="2400" CurWidth="5000" CurHeight="2400"/>
      <LINESHAPE Width="0" Style="Solid" EndCap="Flat" Alpha="0"/>
      <DRAWTEXT><TEXTMARGIN Left="0" Right="0" Top="0" Bottom="0"/><PARALIST>
        <P><TEXT><TABLE RowCount="1" ColCount="1">
          <SHAPEOBJECT><SIZE Width="4000" Height="1200"/></SHAPEOBJECT>
          <ROW><CELL ColAddr="0" RowAddr="0" Width="4000" Height="1200"><PARALIST>
            <P><TEXT><CHAR>글상자표전용단어</CHAR></TEXT></P>
          </PARALIST></CELL></ROW>
        </TABLE></TEXT></P>
      </PARALIST></DRAWTEXT>
    </DRAWINGOBJECT>
  </RECTANGLE></TEXT></P>
</SECTION></BODY><TAIL/></HWPML>"#;

fn nested() -> DocumentCore {
    DocumentCore::from_bytes(NESTED_HML.as_bytes()).expect("중첩 표 픽스처가 열려야 한다")
}

fn textbox_table() -> DocumentCore {
    DocumentCore::from_bytes(TEXTBOX_TABLE_HML.as_bytes())
        .expect("글상자 안 표 픽스처가 열려야 한다")
}

#[test]
fn nested_table_text_is_found() {
    // 이 계약의 핵심. 종전에는 아래 두 단어가 어떤 질의로도 잡히지 않았다.
    let doc = nested();
    for word in ["본문전용단어", "바깥셀단어", "중첩셀단어", "더깊은셀단어"] {
        assert_eq!(
            hit_count(&doc, word),
            1,
            "{word} 를 찾지 못했습니다 (중첩 표 순회 누락)"
        );
    }
}

#[test]
fn search_finds_table_text_inside_textbox() {
    let doc = textbox_table();
    assert_eq!(
        hit_count(&doc, "글상자표전용단어"),
        1,
        "글상자 안 표 텍스트를 검색이 놓치면 안 됩니다"
    );
}

#[test]
fn replace_all_native_replaces_nested_only_token() {
    // 검색과 치환 엔진은 중첩 표 전용 토큰을 같은 범위로 다룬다.
    let mut doc = nested();
    assert_eq!(hit_count(&doc, "더깊은셀단어"), 1);
    let result = doc
        .replace_all_native("더깊은셀단어", "치환됨", true)
        .expect("replace_all_native 는 실패하지 않아야 한다");
    let v: serde_json::Value =
        serde_json::from_str(&result).unwrap_or_else(|e| panic!("{e}: {result}"));
    assert_eq!(v["ok"], true, "{result}");
    assert_eq!(
        v["count"], 1,
        "중첩 전용 토큰도 한 번 치환되어야 합니다: {result}"
    );
    assert_eq!(hit_count(&doc, "더깊은셀단어"), 0);
    assert_eq!(hit_count(&doc, "치환됨"), 1);
}
