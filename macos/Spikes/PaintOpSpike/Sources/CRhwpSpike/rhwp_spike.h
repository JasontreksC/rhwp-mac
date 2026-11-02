#ifndef RHWP_SPIKE_H
#define RHWP_SPIKE_H

// bindings/Native 가 내보내는 C ABI 중 스파이크가 쓰는 함수만 선언한다.
// 반환 문자열은 반드시 rhwp_string_free 로 해제한다.
char *rhwp_page_layer_tree(const char *input_path, int page);
void rhwp_string_free(char *value);

#endif
