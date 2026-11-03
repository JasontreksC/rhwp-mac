# Third-Party Licenses

rhwp-mac이 사용하는 서드파티 라이브러리와 리소스의 라이선스 목록이다.

기준 파일:

- `Cargo.toml` / `Cargo.lock` (`rhwp` v0.8.7)
- `ttfs/opensource/`, `ttfs/redistributable/`의 글꼴과 동봉 라이선스

Swift 쪽(`macos/`)은 Apple 시스템 프레임워크만 쓰며 외부 패키지에 의존하지 않는다.

---

## Rust 크레이트

### 직접 의존성

워크스페이스 멤버(`rhwp`, `rhwp-native-ffi`, `rhwp-ooxml-chart`, `rhwp-password-crypto`)가 직접 선언한 외부 크레이트다.
`getrandom`은 두 버전이 함께 들어 있다.

| 크레이트 | 버전 | 라이선스 | 저장소 | 비고 |
|---------|------|---------|--------|------|
| aes | 0.9.3 | MIT OR Apache-2.0 | RustCrypto/block-ciphers | HWP 암호 문서 복호화(AES) |
| base64 | 0.23.1 | MIT OR Apache-2.0 | marshallpierce/rust-base64 | Base64 인코딩 |
| blake3 | 1.8.7 | CC0-1.0 OR Apache-2.0 OR Apache-2.0 WITH LLVM-exception | BLAKE3-team/BLAKE3 | 레이어 트리 자원 해시 |
| byteorder | 1.5.0 | Unlicense OR MIT | BurntSushi/byteorder | 바이너리 endian 처리 |
| cbc | 0.2.1 | MIT OR Apache-2.0 | RustCrypto/block-modes | 비밀번호 암호화 CBC 모드 |
| cfb | 0.15.0 | MIT | mdsteele/rust-cfb | OLE Compound File |
| codepage | 0.1.3 | Apache-2.0 OR MIT | hsivonen/codepage | 코드페이지 처리 |
| crc32fast | 1.5.2 | MIT OR Apache-2.0 | srijs/rust-crc32fast | HWP3 암호 키 검증 |
| des | 0.9.0 | MIT OR Apache-2.0 | RustCrypto/block-ciphers | HWP3 암호 |
| embedded-io | 0.7.1 | MIT OR Apache-2.0 | rust-embedded/embedded-hal | IO trait |
| encoding_rs | 0.8.42 | (Apache-2.0 OR MIT) AND BSD-3-Clause | hsivonen/encoding_rs | 문자 인코딩 |
| flate2 | 1.1.10 | MIT OR Apache-2.0 | rust-lang/flate2-rs | 압축·해제 |
| getrandom | 0.3.4 | MIT OR Apache-2.0 | rust-random/getrandom | 암호 문서 저장용 난수 |
| getrandom | 0.4.3 | MIT OR Apache-2.0 | rust-random/getrandom | 암호 문서 저장용 난수 |
| hmac | 0.13.0 | MIT OR Apache-2.0 | RustCrypto/MACs | HWPX 무결성 |
| image | 0.25.10 | MIT OR Apache-2.0 | image-rs/image | BMP·JPEG·PNG·TIFF 디코딩 |
| paste | 1.0.15 | MIT OR Apache-2.0 | dtolnay/paste | 매크로 보조 |
| pbkdf2 | 0.13.0 | MIT OR Apache-2.0 | RustCrypto/password-hashes | HWPX 키 파생 |
| pcx | 0.2.5 | MIT OR Apache-2.0 OR WTFPL | kryptan/pcx | PCX 이미지 디코딩 |
| proptest | 1.11.0 | MIT OR Apache-2.0 | proptest-rs/proptest | 속성 기반 시험(dev) |
| quick-xml | 0.42.0 | MIT | tafia/quick-xml | HWPX XML 파싱 |
| roxmltree | 0.21.1 | MIT OR Apache-2.0 | RazrFalcon/roxmltree | XML 검증·정규화 |
| rustybuzz | 0.20.1 | MIT | harfbuzz/rustybuzz | 글자 shaping |
| serde | 1.0.229 | MIT OR Apache-2.0 | serde-rs/serde | 직렬화 |
| serde_json | 1.0.151 | MIT OR Apache-2.0 | serde-rs/json | JSON 직렬화 |
| sha1 | 0.11.0 | MIT OR Apache-2.0 | RustCrypto/hashes | HWPX 암호 키 파생 |
| sha2 | 0.11.0 | MIT OR Apache-2.0 | RustCrypto/hashes | 해시 |
| snafu | 0.9.2 | MIT OR Apache-2.0 | shepmaster/snafu | 오류 처리 |
| strum | 0.28.0 | MIT | Peternator7/strum | enum derive |
| subsetter | 0.2.6 | MIT OR Apache-2.0 | typst/subsetter | 글꼴 subset |
| svgtypes | 0.16.1 | Apache-2.0 OR MIT | linebender/svgtypes | SVG 값 파싱 |
| ttf-parser | 0.25.1 | MIT OR Apache-2.0 | harfbuzz/ttf-parser | 글꼴 파싱 |
| unicode-properties | 0.1.4 | MIT/Apache-2.0 | unicode-rs/unicode-properties | 유니코드 문자 분류 |
| unicode-segmentation | 1.13.3 | MIT OR Apache-2.0 | unicode-rs/unicode-segmentation | grapheme·word 분할 |
| unicode-width | 0.2.2 | MIT OR Apache-2.0 | unicode-rs/unicode-width | 문자 폭 계산 |
| zip | 8.6.0 | MIT | zip-rs/zip2 | HWPX ZIP 처리 |

### 전체 Rust 의존성 요약

`cargo metadata --locked` 기준 package entry는 162개이며, 그중 registry source를 가진 외부 Rust 크레이트는
158개다. 나머지 4개는 이 저장소의 workspace 패키지다.

주요 라이선스군:

- MIT / Apache-2.0 dual license 계열
- MIT 단독
- BSD-2-Clause / BSD-3-Clause
- Zlib
- Unlicense
- 0BSD
- ISC
- Unicode-3.0
- CC0-1.0 / Apache-2.0 WITH LLVM-exception (`blake3`)
- WTFPL 대체 선택지 포함 (`pcx`, MIT/Apache 선택 가능)

> 모든 Rust 의존성은 MIT, Apache-2.0, BSD, Zlib, Unlicense, 0BSD, ISC 등 permissive license 계열이거나
> permissive option을 포함하며, 이 저장소의 MIT 라이선스와 호환된다.

---

## 글꼴

Git으로 추적하는 글꼴은 재배포가 허용된 것만이다. 저작권 보호 대상인 한컴·Microsoft 글꼴은 저장소에 두지 않는다
(`ttfs/hwp/`, `ttfs/windows/`는 `.gitignore` 처리된 로컬 자리다).

| 글꼴 | 위치 | 라이선스 | 출처 |
|------|------|---------|------|
| Noto Sans KR (Regular, ExtraLight subset) | `ttfs/opensource/` | SIL Open Font License 1.1 (`NotoSansKR-OFL.txt`) | Google Fonts `ofl/notosanskr` |
| Source Han Serif K Old Hangul subset | `ttfs/opensource/` | SIL Open Font License 1.1 (`SourceHanSerifK-OFL.txt`) | Adobe / Google |
| 행복고딕 (Happiness Sans VF) | `ttfs/redistributable/happiness-sans/` | 권리자의 무료 사용·배포 허가 (`HapinessSans_License.pdf` 동봉) | 행복나눔재단 (thehyundaifont.com) |

---

## 직접 포팅한 알고리즘

### Volexity hwp-extract

- 출처: [volexity/hwp-extract](https://github.com/volexity/hwp-extract), commit
  `e5f8b5e1590dee973630666e687e919fa70da2e2`
- 참조 파일: `src/hwp_extract/encrypt.py`
- 적용 위치: `src/parser/crypto.rs`의 HWP5 EncryptVersion 4 키 파생 및 비트 단위
  AES-CFB 복호화
- 라이선스: BSD-3-Clause

Modified BSD License

_Copyright © `2024`, `Volexity, Inc`_

_All rights reserved._

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright
   notice, this list of conditions and the following disclaimer.
2. Redistributions in binary form must reproduce the above copyright
   notice, this list of conditions and the following disclaimer in the
   documentation and/or other materials provided with the distribution.
3. Neither the name of the `Volexity, Inc` nor the
   names of its contributors may be used to endorse or promote products
   derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS “AS IS” AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL `Volexity, Inc` BE LIABLE FOR ANY
DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

---

## 참조한 오픈소스 프로젝트 (스펙·설계 참조)

rhwp-mac은 아래 프로젝트들의 **코드를 직접 복사하지 않으며**, 공개된 스펙 정보(enum 값·속성 기본값·태그 이름·검증 규칙 등)만 참조한다.
Apache-2.0 라이선스 고지 의무는 본 문서, 관련 기술 문서, 그리고 각 참조 파일의 헤더 주석으로 충족한다.

| 프로젝트 | 라이선스 | 참조 범위 | 이 저장소의 위치 |
|---------|---------|----------|-----------|
| [hancom-io/hwpx-owpml-model](https://github.com/hancom-io/hwpx-owpml-model) | Apache-2.0 © 2022 Hancom Inc. | HWPX enum 정의, 속성 기본값, 태그 전체 집합, canonical 속성·자식 순서 | `src/serializer/hwpx/canonical_defaults.rs`, `src/serializer/hwpx/{header,table,shape,picture}.rs`, `mydocs/tech/hwpx_hancom_reference.md` |
| [hancom-io/dvc](https://github.com/hancom-io/dvc) | Apache-2.0 © 2022 Hancom Inc. | HWPX 검증 규칙 JSON 스키마, errorCode 체계 | `mydocs/tech/hwpx_dvc_reference.md` |

---

## 라이선스 호환성

이 저장소는 **MIT 라이선스**로 배포된다(업스트림 rhwp와 같다).

- MIT, Apache-2.0, BSD, Zlib, Unlicense, 0BSD, ISC, CC0 — MIT와 호환되는 permissive license 계열
- `encoding_rs`의 BSD-3-Clause 조항은 고지 의무를 요구하며, 이 문서로 충족
- `pcx`는 WTFPL 대체 선택지를 포함하지만 MIT/Apache-2.0 선택지가 있어 MIT 배포와 호환
- 오픈 글꼴은 SIL OFL 1.1 등 재배포 가능한 라이선스만 Git에 포함
- 앱에 글꼴을 번들하게 되면 그 시점에 이 문서와 글꼴별 라이선스 고지를 함께 갱신한다

---

*이 문서는 `Cargo.toml`, `Cargo.lock`, `ttfs/` 기준으로 현행화되었으며, 의존성이나 글꼴이 바뀌면 함께 갱신해야 한다.*
