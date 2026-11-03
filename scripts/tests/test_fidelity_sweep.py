"""`macos/scripts/fidelity-sweep.py` 의 짝짓기 규칙과 문서 단위 쪽수 판정 시험.

짝짓기 시험은 저장소의 실제 `samples/`·`pdf/` 이름 구조를 입력으로 쓴다(합성 입력이 아니라 이 규칙이 풀려는 실제 이름들이다).
"""
from __future__ import annotations

import importlib.util
import sys
import unittest
from pathlib import Path

MODULE_PATH = Path(__file__).resolve().parents[2] / "macos" / "scripts" / "fidelity-sweep.py"
SPEC = importlib.util.spec_from_file_location("fidelity_sweep", MODULE_PATH)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError(f"fidelity-sweep 모듈을 불러올 수 없습니다: {MODULE_PATH}")
SWEEP = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = SWEEP
SPEC.loader.exec_module(SWEEP)

ROOT = SWEEP.ROOT


def pdfs_of(pairs, document: str) -> set[str]:
    return {str(pdf.relative_to(ROOT)) for doc, pdf in pairs if str(doc.relative_to(ROOT)) == document}


class ParsePdfSuffixTests(unittest.TestCase):
    def test_format_engine_and_variant_tokens(self) -> None:
        self.assertEqual(SWEEP.parse_pdf_suffix("-hwp-2024"), {"format": "hwp", "engine": 2024, "variant": False})
        self.assertEqual(SWEEP.parse_pdf_suffix("-2022"), {"format": None, "engine": 2022, "variant": False})
        self.assertEqual(SWEEP.parse_pdf_suffix("-hwpx-kopub-2020")["variant"], True)
        self.assertEqual(SWEEP.parse_pdf_suffix("-2010-no-ttf")["variant"], True)
        # 한글 2010 엔진 PDF 는 변형이다(상류 원장 머리말: "다른 세대").
        self.assertEqual(SWEEP.parse_pdf_suffix("-2010")["variant"], True)
        self.assertEqual(SWEEP.parse_pdf_suffix(""), {"format": None, "engine": None, "variant": False})

    def test_non_suffix_text_is_not_a_suffix(self) -> None:
        # 이름이 더 이어지는 다른 문서의 PDF 를 이 문서의 것으로 잘못 잡지 않는다.
        self.assertIsNone(SWEEP.parse_pdf_suffix("-sample"))
        self.assertIsNone(SWEEP.parse_pdf_suffix("-hwp5-2020"))
        # 엔진 연도·형식은 PDF 하나에 하나뿐이다.
        self.assertIsNone(SWEEP.parse_pdf_suffix("-2010-2020"))
        self.assertIsNone(SWEEP.parse_pdf_suffix("-hwp-hwpx-2020"))


class DiscoverPairsTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.pairs = SWEEP.discover_pairs()
        cls.all_pairs = SWEEP.discover_pairs(include_variants=True)

    def test_2010_engine_pdfs_are_not_paired_by_default(self) -> None:
        # exam_eng-2010.pdf(14쪽)·21_언어-2010.pdf(16쪽)는 한글 2010 엔진 출력이고 같은 문서의 2018~2022 엔진 PDF 는 8쪽·15쪽이다.
        exam = pdfs_of(self.pairs, "samples/exam_eng.hwp")
        self.assertNotIn("samples/exam_eng-2010.pdf", exam)
        self.assertIn("samples/exam_eng-2020.pdf", exam)
        self.assertIn("pdf/exam_eng-hwp-2020.pdf", exam)
        self.assertIn("samples/exam_eng-2010.pdf", pdfs_of(self.all_pairs, "samples/exam_eng.hwp"))
        language = pdfs_of(self.pairs, "samples/21_언어_기출_편집가능본.hwp")
        self.assertNotIn("samples/21_언어_기출_편집가능본-2010.pdf", language)

    def test_untagged_pdf_pairs_with_every_extension(self) -> None:
        # 형식 접미사가 없는 PDF 가 .hwp 에만 짝지어지면(옛 규칙) .hwpx 에서 나온 PDF 와의 쪽수 불일치가 거짓 신호가 된다.
        self.assertIn("pdf/SO-SUEOP-2024.pdf", pdfs_of(self.pairs, "samples/SO-SUEOP.hwp"))
        self.assertIn("pdf/SO-SUEOP-2024.pdf", pdfs_of(self.pairs, "samples/SO-SUEOP.hwpx"))

    def test_tagged_pdf_pairs_only_with_its_format(self) -> None:
        self.assertIn("pdf/SO-SUEOP-hwp-2020.pdf", pdfs_of(self.pairs, "samples/SO-SUEOP.hwp"))
        self.assertNotIn("pdf/SO-SUEOP-hwp-2020.pdf", pdfs_of(self.pairs, "samples/SO-SUEOP.hwpx"))
        self.assertIn("pdf/SO-SUEOP-hwpx-2024.pdf", pdfs_of(self.pairs, "samples/SO-SUEOP.hwpx"))
        self.assertNotIn("pdf/SO-SUEOP-hwpx-2024.pdf", pdfs_of(self.pairs, "samples/SO-SUEOP.hwp"))

    def test_two_year_tokens_are_not_a_suffix(self) -> None:
        # `hwp3-sample16-hwp5-2010.hwp` 의 PDF 이름 `...-2010-2020.pdf` 의 `-2010` 은 엔진 연도가 아니라 문서 이름의 일부다.
        plain = pdfs_of(self.pairs, "samples/hwp3-sample16-hwp5.hwp")
        year2010 = pdfs_of(self.pairs, "samples/hwp3-sample16-hwp5-2010.hwp")
        self.assertNotIn("pdf/hwp3-sample16-hwp5-2010-2020.pdf", plain)
        self.assertIn("pdf/hwp3-sample16-hwp5-2010-2020.pdf", year2010)

    def test_ambiguous_name_pairs_with_every_candidate_document(self) -> None:
        # `k-water-rfp-2024.pdf` 는 문서 `k-water-rfp` 의 2024 엔진 PDF 일 수도, 문서 `k-water-rfp-2024` 의 PDF 일 수도 있다.
        # 하나만 고르면(옛 규칙 또는 가장 긴 이름) 다른 쪽 문서가 자기 PDF 를 잃는다.
        self.assertIn("pdf/k-water-rfp-2024.pdf", pdfs_of(self.pairs, "samples/k-water-rfp.hwp"))
        self.assertIn("pdf/k-water-rfp-2024.pdf", pdfs_of(self.pairs, "samples/k-water-rfp-2024.hwp"))

    def test_flat_pdf_pairs_with_a_subdirectory_document(self) -> None:
        # 평탄한 PDF 는 하위 폴더 문서의 것일 수 있다(옛 규칙 유지): pdf/18096141-…-2020.pdf ↔ samples/issue6873/….hwp
        self.assertIn("pdf/18096141-gyeongju-gas-subsidy-plan-2020.pdf",
                      pdfs_of(self.pairs, "samples/issue6873/18096141-gyeongju-gas-subsidy-plan.hwp"))

    def test_subdirectory_pdf_does_not_pair_across_directories(self) -> None:
        # pdf/task4097/SO-SUEOP.pdf 는 samples/task4097/ 의 문서 것이지 samples/SO-SUEOP.hwp 의 것이 아니다.
        for document in ("samples/SO-SUEOP.hwp", "samples/SO-SUEOP.hwpx"):
            self.assertNotIn("pdf/task4097/SO-SUEOP.pdf", pdfs_of(self.pairs, document))


class PairKeyTests(unittest.TestCase):
    def test_result_folders_are_unique_per_pair(self) -> None:
        # 같은 PDF 가 두 문서에 짝지어져도 결과 폴더가 겹치지 않는다(겹치면 병렬 측정이 서로의 TSV를 깨뜨린다).
        pairs = SWEEP.discover_pairs()
        keys = [SWEEP.pair_key(doc, pdf) for doc, pdf in pairs]
        self.assertEqual(len(keys), len(set(keys)))
        self.assertNotEqual(
            SWEEP.pair_key(ROOT / "samples" / "SO-SUEOP.hwp", ROOT / "pdf" / "SO-SUEOP-2024.pdf"),
            SWEEP.pair_key(ROOT / "samples" / "SO-SUEOP.hwpx", ROOT / "pdf" / "SO-SUEOP-2024.pdf"),
        )


class CountVerdictTests(unittest.TestCase):
    @staticmethod
    def row(document: str, ours: int, pdf: int) -> dict:
        return {"document": document, "rhwp_total": ours, "pdf_total": pdf, "count_match": int(ours == pdf)}

    def test_verdict_uses_every_pdf_of_the_document(self) -> None:
        rows = [
            self.row("a.hwp", 8, 8), self.row("a.hwp", 8, 8),   # 전부 일치
            self.row("b.hwp", 23, 22), self.row("b.hwp", 23, 23),  # PDF끼리 갈림(한컴 자신이 22/23)
            self.row("c.hwp", 40, 20), self.row("c.hwp", 40, 21),  # 어느 PDF와도 다름
        ]
        self.assertEqual(SWEEP.count_verdicts(rows), {"a.hwp": "일치", "b.hwp": "PDF끼리 갈림", "c.hwp": "불일치"})

    def test_unmeasured_rows_are_ignored(self) -> None:
        rows = [{"document": "d.hwp", "rhwp_total": None, "pdf_total": None, "count_match": None}]
        self.assertEqual(SWEEP.count_verdicts(rows), {})


if __name__ == "__main__":
    unittest.main()
