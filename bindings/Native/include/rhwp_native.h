// rhwp 네이티브 C ABI. 정본 구현은 bindings/Native/src/lib.rs 이다.
//
// 이 헤더와 내보낸 심볼이 어긋나지 않도록 lib.rs 의 단위 테스트가 두 집합을 비교한다.
// 함수를 더하거나 지울 때는 두 곳을 함께 바꾼다.
//
// 규약
// - 문자열 인자는 NUL로 끝나는 UTF-8 이다.
// - `char *` 로 돌려받는 문자열은 항상 JSON 이고, 호출자가 rhwp_string_free 로 해제한다.
//   성공이면 {"ok":true,...}, 실패면 {"ok":false,"error":"..."} 이다.
// - 핸들(RhwpDocument *)은 호출자 소유이며 rhwp_document_free 로 한 번만 해제한다.
// - 핸들은 스레드 안전을 약속하지 않는다. 호출자가 호출을 직렬화해야 한다.

#ifndef RHWP_NATIVE_H
#define RHWP_NATIVE_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// ── 핸들 기반 문서 API: 한 번 열어 두고 반복 질의한다 ───────────────────────

typedef struct RhwpDocument RhwpDocument;

// 경로의 HWP/HWPX/HWP3 파일을 연다. 실패하면 NULL 을 돌려주고, out_error 가 NULL 이 아니면
// 오류 JSON 을 써 준다. 성공하면 *out_error 는 NULL 이 된다.
RhwpDocument *rhwp_document_open(const char *path, char **out_error);

// 메모리의 파일 내용으로 연다. 바이트는 호출 안에서 복사되므로 호출 뒤에 버려도 된다.
RhwpDocument *rhwp_document_open_bytes(const uint8_t *data, size_t len, char **out_error);

// 전체 쪽수. 핸들이 NULL 이거나 이전 호출에서 panic 이 난 문서면 -1.
int32_t rhwp_document_page_count(const RhwpDocument *doc);

// 한 쪽(0부터)의 레이어 트리 JSON.
// {"ok":true,"pageCount":N,"page":P,"layerTree":{...}}
char *rhwp_document_page_layer_tree(const RhwpDocument *doc, uint32_t page);

// 모든 쪽의 크기(px, 96dpi). 스크롤 영역과 썸네일 자리를 쪽 그림 없이 잡는 데 쓴다.
// {"ok":true,"pageCount":N,"pages":[{"width":W,"height":H},...]}
char *rhwp_document_page_sizes(const RhwpDocument *doc);

// 핸들을 해제한다. NULL 은 무시한다.
void rhwp_document_free(RhwpDocument *doc);

// ── 공통 ────────────────────────────────────────────────────────────────────

// 이 라이브러리가 돌려준 문자열(out_error 포함)을 해제한다. NULL 은 무시한다.
void rhwp_string_free(char *value);

#ifdef __cplusplus
}
#endif

#endif
