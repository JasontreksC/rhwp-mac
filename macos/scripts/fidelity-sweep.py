#!/usr/bin/env python3
"""샘플 문서 묶음의 렌더 충실도를 쪽별로 자동 측정한다.

각 (문서, 한컴 출력 PDF) 쌍마다
  1) `rhwp-render <문서> --all`  로 우리 렌더러의 쪽 PNG를,
  2) `rhwp-render --pdf <PDF>`   로 기준 PDF의 쪽 PNG를 (둘 다 96dpi, 흰 배경) 만들고,
  3) `scripts/visual_sweep.py --silhouette-only --png-pair` 로 2px 이웃 관용 내용 실루엣 일치율을 쪽별로 구한다.
결과를 쪽별·문서별 TSV와 요약으로 모은다. 4단계 렌더러 작업의 "쪽별 일치율이 자동 측정됨"을 지키는 도구다.

사용법 (저장소 루트에서)
  macos/scripts/fidelity-sweep.py --discover --pages 1-6 --limit 60
  macos/scripts/fidelity-sweep.py --pair samples/KTX.hwp pdf/KTX-2022.pdf --pages 1-27
  macos/scripts/fidelity-sweep.py --discover --match 보건소          (이름에 문자열이 든 쌍만)
  macos/scripts/fidelity-sweep.py --discover --dry-run               (짝 목록만 보고 측정하지 않는다)

주의
- 90% 미만은 "새 회귀 시험·기준 파일을 추가하지 않는다"는 게이트이지 이 도구의 실패가 아니다(AGENTS.md 시각 검증).
- 현재 일치율은 한컴 글꼴이 이 Mac에 없어 글꼴 대체가 지배적이다. `fonts.tsv`가 어떤 글꼴이 무엇으로 대체됐는지 센다.
- 쪽수가 한컴 PDF와 다르면 점수와 별개로 `count_match=0`으로 기록한다(두 쪽수의 공통 쪽만 비교한다). 같은 문서의 PDF가 여럿이면
  문서 단위로 판정한다(`count_docs.tsv`): 어느 PDF와도 다른 문서만 진짜 불일치다. 짝짓기 규칙은 `discover_pairs` 주석.
- 산출물(PNG·TSV)은 기본적으로 git 이 무시하는 `output/fidelity/` 아래에 만든다. 커밋하지 않는다.
"""
import argparse
import concurrent.futures
import datetime
import re
import statistics
import subprocess
import sys
import unicodedata
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PACKAGE = ROOT / "macos" / "RhwpKit"
RENDER = PACKAGE / ".build" / "release" / "rhwp-render"
SWEEP = ROOT / "scripts" / "visual_sweep.py"
GATE = 90.0  # AGENTS.md: 정확히 90%는 통과


def build_tool() -> None:
    """XCFramework(증분)와 rhwp-render 를 빌드한다."""
    subprocess.run([str(ROOT / "macos" / "scripts" / "build-xcframework.sh")], check=True, stdout=subprocess.DEVNULL)
    subprocess.run(
        ["swift", "build", "-c", "release", "--package-path", str(PACKAGE), "--product", "rhwp-render"],
        check=True, stdout=subprocess.DEVNULL,
    )


def parse_pages(text: str) -> list[int]:
    """`1-8`, `3`, `1,3,5-7` → 쪽 번호 목록(1부터)."""
    pages: list[int] = []
    for part in text.split(","):
        low, _, high = part.strip().partition("-")
        pages.extend(range(int(low), int(high or low) + 1))
    return sorted(set(pages))


# PDF 이름의 접미사 토큰. `<문서 이름>` 뒤에 이 토큰들이 어떤 순서로든 붙는다:
#   -hwp / -hwpx  : PDF 를 만든 원본 형식(없으면 모른다)
#   -20NN         : PDF 를 만든 한컴 엔진 연도(2010·2018·2020·2022·2024)
#   -kopub / -no-ttf : 글꼴 설치 조건을 바꿔 뽑은 변형
#   -current      : 현재 문서 상태로 다시 뽑은 것
SUFFIX_TOKEN = re.compile(r"-(?:20\d\d|hwpx|hwp|kopub|no-ttf|current)")
# 한컴 2010 엔진과 글꼴 조건 변형은 이 저장소가 맞추는 2018+ 엔진과 같은 정답지가 아니다(아래 discover_pairs 주석).
VARIANT_TOKENS = {"-kopub", "-no-ttf", "-2010"}


def parse_pdf_suffix(remainder: str) -> dict | None:
    """`<문서 이름>` 뒤의 나머지 문자열을 접미사 토큰으로 풀어 형식·엔진·변형을 돌려준다. 토큰만으로 이뤄지지 않으면 None."""
    tokens = SUFFIX_TOKEN.findall(remainder)
    if "".join(tokens) != remainder:
        return None
    formats = [t[1:] for t in tokens if t in ("-hwp", "-hwpx")]
    years = [int(t[1:]) for t in tokens if re.fullmatch(r"-20\d\d", t)]
    # 엔진 연도·원본 형식은 PDF 하나에 하나뿐이다. 둘 이상이면 문서 이름의 일부가 섞인 것이다
    # (`hwp3-sample16-hwp5-2010-2020.pdf` 는 문서 `hwp3-sample16-hwp5` 의 접미사 `-2010-2020` 이 아니라
    #  문서 `hwp3-sample16-hwp5-2010` 의 접미사 `-2020` 이다).
    if len(years) > 1 or len(formats) > 1:
        return None
    return {
        "format": formats[-1] if formats else None,
        "engine": years[-1] if years else None,
        "variant": any(t in VARIANT_TOKENS for t in tokens),
    }


def relative_directory(path: Path, base: Path) -> str:
    """`base` 아래의 상대 디렉터리(최상위면 빈 문자열)."""
    relative = path.parent.relative_to(base)
    return "" if str(relative) == "." else unicodedata.normalize("NFC", str(relative))


def discover_pairs(include_variants: bool = False) -> list[tuple[Path, Path]]:
    """`pdf/`·`samples/`의 한컴 PDF를 같은 문서에 짝짓는다.

    이전 규칙(PDF 하나 → 이름이 같은 문서 중 사전순 첫째)은 세 가지 측정 산물을 만들었다.
      1) 한글 2010 엔진이 뽑은 PDF(`exam_eng-2010.pdf` 14쪽, `21_언어_기출_편집가능본-2010.pdf` 16쪽)와 짝지어 "쪽수 불일치"를 냈다.
         같은 문서의 2018~2022 엔진 PDF 4개는 모두 우리와 같은 8쪽·15쪽이다. 2010 엔진과 `-kopub`·`-no-ttf` 글꼴 조건 변형은
         상류 정답지 원장(`tests/fixtures/oracle_page_count_baseline.tsv` 머리말)도 "다른 세대·섞지 않는다"며 정답지에서 뺀다.
      2) 형식 접미사가 없는 PDF(`SO-SUEOP-2024.pdf`)를 `.hwp` 와 `.hwpx` 중 사전순 첫째(`.hwp`)에만 짝지었다. 형식을 모르면 둘 다 후보다.
      3) 같은 이름의 문서가 다른 폴더에 있을 때(`samples/foo.hwp`, `samples/hwpx/hancom-hwp/foo.hwp`) 엉뚱한 쪽을 골랐다.
    새 규칙:
      - PDF 이름이 `<문서 이름>` + 접미사 토큰(`parse_pdf_suffix`)이면 그 문서의 PDF다. 연도·형식 토큰이 둘 이상이면 접미사가 아니다
        (`hwp3-sample16-hwp5-2010-2020.pdf` 는 문서 `hwp3-sample16-hwp5-2010` 의 PDF 다). 이름만으로 문서가 둘 이상으로 풀리면(`k-water-rfp-2024.pdf`:
        문서 `k-water-rfp` 의 2024 엔진 PDF 일 수도, 문서 `k-water-rfp-2024` 의 PDF 일 수도 있다) 모두 짝짓는다. `pdf/` 는 하위 폴더까지 본다.
      - 형식 접미사(-hwp/-hwpx)가 있으면 그 확장자의 문서만, 없으면 확장자가 다른 문서 모두가 후보다(같은 PDF가 두 쌍이 된다).
      - `pdf/` 하위 폴더의 PDF는 `samples/` 의 같은 하위 폴더 문서에만 짝짓는다(없으면 버린다). `pdf/` 최상위 PDF는 같은 이름·확장자의
        문서가 여러 폴더에 있으면 최상위 폴더 문서, 없으면 사전순 첫째(옛 규칙 그대로: 평탄한 PDF 는 하위 폴더 문서의 것일 수 있다).
      - 기본은 2010 엔진·`-kopub`·`-no-ttf` PDF를 뺀다(`include_variants=True` 로 다시 넣는다).
    같은 문서에 PDF가 여러 개일 수 있으므로 쪽수 판정은 `write_reports` 가 문서 단위로 모은다.
    """
    documents: list[Path] = []
    for extension in ("hwp", "hwpx", "hwp3"):
        documents += sorted((ROOT / "samples").rglob(f"*.{extension}"))
    stems: dict[str, list[Path]] = {}
    for path in documents:
        stems.setdefault(unicodedata.normalize("NFC", path.stem), []).append(path)
    pdfs = sorted(list((ROOT / "pdf").rglob("*.pdf")) + list((ROOT / "samples").glob("*.pdf")))
    pairs: list[tuple[Path, Path]] = []
    for pdf in pdfs:
        name = unicodedata.normalize("NFC", pdf.stem)
        # 접미사 토큰으로만 풀리는 문서 이름이 여럿이면 모두 후보다(`k-water-rfp-2024.pdf` 는 `k-water-rfp` 의 2024 엔진 PDF 일 수도,
        # `k-water-rfp-2024` 문서의 PDF 일 수도 있다. 이름만으로는 가를 수 없으니 둘 다 짝짓고 쪽수 판정이 문서 단위로 모은다).
        matches = []
        for stem in stems:
            if name.startswith(stem):
                parsed = parse_pdf_suffix(name[len(stem):])
                if parsed is not None and (include_variants or not parsed["variant"]):
                    matches.append((stem, parsed))
        for stem, suffix in matches:
            pairs += pair_group(stems[stem], suffix, pdf)
    return pairs


def pair_group(candidates: list[Path], suffix: dict, pdf: Path) -> list[tuple[Path, Path]]:
    """한 PDF와 이름이 맞는 문서 후보들에서 실제로 짝지을 문서를 고른다(확장자당 하나)."""
    if suffix["format"]:
        candidates = [p for p in candidates if p.suffix == f".{suffix['format']}"]
    # 같은 확장자 안에서 폴더가 여럿이면 하나만 고른다. 확장자가 다른 문서는 따로 남긴다.
    by_extension: dict[str, list[Path]] = {}
    for path in candidates:
        by_extension.setdefault(path.suffix, []).append(path)
    pdf_base = ROOT / ("pdf" if (ROOT / "pdf") in pdf.parents else "samples")
    pdf_directory = relative_directory(pdf, pdf_base)
    pairs: list[tuple[Path, Path]] = []
    for group in by_extension.values():
        same = [p for p in group if relative_directory(p, ROOT / "samples") == pdf_directory]
        if pdf_directory:
            # 하위 폴더의 PDF는 같은 하위 폴더의 문서에만 짝짓는다(`pdf/task4097/SO-SUEOP.pdf` 는 `samples/SO-SUEOP.hwp` 가 아니다).
            if same:
                pairs.append((same[0], pdf))
            continue
        top = [p for p in group if relative_directory(p, ROOT / "samples") == ""]
        pairs.append(((same or top or group)[0], pdf))
    return pairs


def safe_key(path: Path, keep_suffix: bool = False) -> str:
    """결과 폴더 이름. 같은 문서가 여러 기준 PDF(2020·2024 등)와 짝지어지고 같은 이름의 문서가 폴더만 달리 있을 수 있어
    저장소 상대 경로로 정한다(이름만 쓰면 서로의 결과를 덮어쓴다). 문서는 `.hwp` 와 `.hwpx` 가 이름을 공유하므로 확장자를 남긴다."""
    relative = path.relative_to(ROOT)
    if not keep_suffix:
        relative = relative.with_suffix("")
    return re.sub(r"[^0-9A-Za-z가-힣_.-]+", "_", str(relative))[:120]


def pair_key(document: Path, pdf: Path) -> str:
    """쌍의 결과 폴더 이름. 같은 PDF가 문서 둘 이상에 짝지어질 수 있으므로(형식 접미사가 없는 PDF, 이름이 겹치는 문서) 문서도 넣는다.
    넣지 않으면 두 쌍이 같은 폴더에 동시에 쓰다 서로의 PNG·TSV를 깨뜨린다."""
    return f"{safe_key(pdf)}@{safe_key(document, keep_suffix=True)[-70:]}"


def run(command: list[str], timeout: int) -> subprocess.CompletedProcess:
    return subprocess.run(command, capture_output=True, text=True, timeout=timeout)


def total_pages(output: str) -> int | None:
    match = re.search(r"총 (\d+)쪽", output)
    return int(match.group(1)) if match else None


def document_folder(out: Path, document: Path) -> Path:
    """문서 하나의 렌더 결과 폴더. 같은 문서에 PDF가 여럿이어도 렌더는 한 번만 한다."""
    return out / "_documents" / safe_key(document, keep_suffix=True)


def measure_document(document: Path, pdfs: list[Path], out: Path, pages: list[int], timeout: int,
                     dump_json: bool = False) -> list[dict]:
    """문서 하나를 한 번 그리고, 그 문서의 PDF마다 한 쌍씩 측정한다."""
    folder = document_folder(out, document)
    selection = ",".join(str(p) for p in pages)
    command = [str(RENDER), str(document), "--all", str(folder / "rhwp"), "--pages", selection, "--scale", "1"]
    if dump_json:
        command += ["--json", str(folder / "json")]
    try:
        rendered: subprocess.CompletedProcess | None = run(command, timeout)
    except subprocess.TimeoutExpired:
        rendered = None
    return [measure(document, pdf, out, pages, timeout, rendered) for pdf in pdfs]


def measure(document: Path, pdf: Path, out: Path, pages: list[int], timeout: int,
            rendered: subprocess.CompletedProcess | None) -> dict:
    """한 쌍을 측정한다. 실패해도 예외를 던지지 않고 status 에 사유를 담는다. `rendered` 는 문서의 렌더 결과(공유)다."""
    key = pair_key(document, pdf)
    folder = out / key
    rhwp_dir, pdf_dir = document_folder(out, document) / "rhwp", folder / "pdf"
    row = {"key": key, "document": str(document.relative_to(ROOT)), "pdf": str(pdf.relative_to(ROOT)),
           "rhwp_total": None, "pdf_total": None, "count_match": None, "pages": [], "fonts": {}, "skipped": {}, "status": ""}
    selection = ",".join(str(p) for p in pages)
    if rendered is None:
        row["status"] = "시간 초과"
        return row
    try:
        rasterized = run([str(RENDER), "--pdf", str(pdf), str(pdf_dir), "--pages", selection, "--scale", "1"], timeout)
    except subprocess.TimeoutExpired:
        row["status"] = "시간 초과"
        return row
    if rendered.returncode != 0:
        row["status"] = "렌더 실패: " + (rendered.stderr.strip().splitlines() or ["?"])[-1][:120]
        return row
    if rasterized.returncode != 0:
        row["status"] = "PDF 래스터 실패: " + (rasterized.stderr.strip().splitlines() or ["?"])[-1][:120]
        return row
    row["rhwp_total"] = total_pages(rendered.stdout)
    row["pdf_total"] = total_pages(rasterized.stdout)
    row["count_match"] = int(row["rhwp_total"] == row["pdf_total"])
    for requested, used in re.findall(r"글꼴 대체: (.+?) → (.+)", rendered.stdout):
        row["fonts"][requested] = used
    # "건너뛴 op: op:equation=3 path:arcTo(approximated)=2" 형식의 집계. 키에 공백이 없다.
    skipped_line = re.search(r"건너뛴 op: (.*)", rendered.stdout)
    if skipped_line and skipped_line.group(1).strip() != "없음":
        for name, count in re.findall(r"(\S+)=(\d+)", skipped_line.group(1)):
            row["skipped"][name] = int(count)

    # 두 쪽수의 공통 쪽만 비교한다.
    limit = min(row["rhwp_total"] or 0, row["pdf_total"] or 0)
    common = [p for p in pages if p <= limit]
    if not common:
        row["status"] = "비교할 쪽 없음"
        return row
    sweep = run([sys.executable, str(SWEEP), "--silhouette-only", "--png-pair", str(rhwp_dir), str(pdf_dir),
                 "--out", str(folder / "sweep"), "--pages", ",".join(str(p) for p in common)], timeout)
    tsv = folder / "sweep" / "silhouette.tsv"
    # visual_sweep 은 90% 미만인 쪽이 있으면 0 이 아닌 코드로 끝난다. 그것은 우리가 가장 알고 싶은 결과이므로 실패로
    # 보지 않고, TSV 가 만들어졌는지로 성공을 판단한다.
    if not tsv.exists():
        row["status"] = "비교 실패: " + (sweep.stderr.strip().splitlines() or sweep.stdout.strip().splitlines() or ["?"])[-1][:120]
        return row
    for line in tsv.read_text(encoding="utf-8").splitlines()[1:]:
        page, percent, *_ = line.split("\t")
        row["pages"].append((int(page), float(percent)))
    row["status"] = "ok" if row["count_match"] else "쪽수 불일치"
    return row


def count_verdicts(rows: list[dict]) -> dict[str, str]:
    """문서별 쪽수 판정. 같은 문서의 PDF가 여럿이면 모두 대조한다.

    "일치"        : 쪽수를 잰 PDF 전부가 우리와 같다.
    "PDF끼리 갈림" : 우리와 같은 PDF도 다른 PDF도 있다. 한컴 엔진·설치 글꼴·형식이 다르면 한컴 자신도 쪽수가 갈린다
                    (`-hwp-2024` 22쪽 대 `-hwpx-2024` 23쪽 등). 우리가 어느 쪽인지 이 도구는 가리지 못하므로 결함으로 세지 않는다.
    "불일치"      : 어느 PDF와도 쪽수가 다르다. 진짜 조사 대상이다.
    """
    groups: dict[str, list[dict]] = {}
    for row in rows:
        if row["rhwp_total"] is not None and row["pdf_total"] is not None:
            groups.setdefault(row["document"], []).append(row)
    verdicts = {}
    for document, group in groups.items():
        agree = sum(row["count_match"] for row in group)
        verdicts[document] = "일치" if agree == len(group) else ("PDF끼리 갈림" if agree else "불일치")
    return verdicts


def write_reports(rows: list[dict], out: Path) -> str:
    """쪽별·문서별 TSV 와 글꼴 집계를 쓰고 사람이 읽을 요약을 돌려준다."""
    verdicts = count_verdicts(rows)
    with (out / "pages.tsv").open("w", encoding="utf-8") as stream:
        stream.write("key\tpage\tmatch_percent\tbelow_90\n")
        for row in rows:
            for page, percent in row["pages"]:
                stream.write(f"{row['key']}\t{page}\t{percent:.3f}\t{int(percent < GATE)}\n")

    with (out / "summary.tsv").open("w", encoding="utf-8") as stream:
        stream.write("key\tdocument\tpdf\trhwp_total\tpdf_total\tcount_match\tcompared\tmin\tmean\tbelow_90\tstatus\tdoc_count_verdict\n")
        for row in rows:
            values = [percent for _, percent in row["pages"]]
            stream.write("\t".join(str(x) for x in [
                row["key"], row["document"], row["pdf"], row["rhwp_total"], row["pdf_total"], row["count_match"],
                len(values), f"{min(values):.3f}" if values else "", f"{statistics.mean(values):.3f}" if values else "",
                sum(v < GATE for v in values), row["status"], verdicts.get(row["document"], ""),
            ]) + "\n")

    # 쪽수가 한 PDF라도 다른 문서만 따로 낸다(문서 하나에 PDF별 쪽수를 한 줄로).
    with (out / "count_docs.tsv").open("w", encoding="utf-8") as stream:
        stream.write("document\trhwp_total\tverdict\tpdf_totals\n")
        by_document: dict[str, list[dict]] = {}
        for row in rows:
            by_document.setdefault(row["document"], []).append(row)
        for document in sorted(by_document):
            if verdicts.get(document, "일치") == "일치":
                continue
            group = by_document[document]
            totals = "; ".join(f"{row['pdf_total']}={row['pdf']}" for row in group if row["pdf_total"] is not None)
            stream.write(f"{document}\t{group[0]['rhwp_total']}\t{verdicts[document]}\t{totals}\n")

    fonts: dict[tuple[str, str], int] = {}
    for row in rows:
        for pair in row["fonts"].items():
            fonts[pair] = fonts.get(pair, 0) + 1
    with (out / "fonts.tsv").open("w", encoding="utf-8") as stream:
        stream.write("requested_font\tsubstitute\tdocuments\n")
        for (requested, used), count in sorted(fonts.items(), key=lambda kv: -kv[1]):
            stream.write(f"{requested}\t{used}\t{count}\n")

    # 건너뛴 op 종류별로, 그 종류가 있는 문서와 없는 문서의 쪽 평균 일치율을 견준다(원인 분류의 첫 단서).
    scored = [r for r in rows if r["pages"]]
    def mean_of(group: list[dict]) -> float | None:
        values = [percent for r in group for _, percent in r["pages"]]
        return statistics.mean(values) if values else None
    kinds = sorted({name for r in scored for name in r["skipped"]})
    op_rows = []
    for kind in kinds:
        with_kind = [r for r in scored if kind in r["skipped"]]
        without = [r for r in scored if kind not in r["skipped"]]
        op_rows.append((kind, len(with_kind), sum(r["skipped"][kind] for r in with_kind), mean_of(with_kind), mean_of(without)))
    op_rows.sort(key=lambda x: -x[1])
    with (out / "ops_docs.tsv").open("w", encoding="utf-8") as stream:
        stream.write("skipped_kind\tkey\tdocument\toccurrences\n")
        for r in scored:
            for kind, count in sorted(r["skipped"].items()):
                stream.write(f"{kind}\t{r['key']}\t{r['document']}\t{count}\n")
    with (out / "ops.tsv").open("w", encoding="utf-8") as stream:
        stream.write("skipped_kind\tdocuments\toccurrences\tmean_with\tmean_without\n")
        for kind, docs, count, with_mean, without_mean in op_rows:
            stream.write(f"{kind}\t{docs}\t{count}\t{with_mean:.2f}\t{without_mean:.2f}\n")

    all_pages = [(r["key"], page, percent) for r in scored for page, percent in r["pages"]]
    values = [percent for _, _, percent in all_pages]
    failed = [r for r in rows if not r["pages"]]
    mismatched = [r for r in scored if not r["count_match"]]
    real = sorted(d for d, v in verdicts.items() if v == "불일치")
    split = sorted(d for d, v in verdicts.items() if v == "PDF끼리 갈림")
    lines = [
        f"쌍 {len(rows)}개 (측정 {len(scored)}, 실패 {len(failed)}), 쪽수가 다른 쌍 {len(mismatched)}개",
        f"문서 {len(verdicts)}개 중 쪽수 판정: 어느 PDF와도 다름(진짜 조사 대상) {len(real)}개, "
        f"PDF끼리 갈림(우리와 같은 PDF도 있음) {len(split)}개 — 목록은 count_docs.tsv",
    ]
    if values:
        below = sum(v < GATE for v in values)
        lines += [
            f"측정한 쪽 {len(values)}개: 평균 {statistics.mean(values):.1f}%, 중앙값 {statistics.median(values):.1f}%, "
            f"최저 {min(values):.1f}%",
            f"{GATE:.0f}% 미만 {below}쪽 ({100 * below / len(values):.1f}%), {GATE:.0f}% 이상 {len(values) - below}쪽",
            "가장 나쁜 쪽 10개: " + ", ".join(f"{k} p{p} {v:.0f}%" for k, p, v in sorted(all_pages, key=lambda x: x[2])[:10]),
        ]
    if op_rows:
        lines.append("건너뛴 op 종류(문서 수, 있는 문서 평균 / 없는 문서 평균): " + ", ".join(
            f"{k} ({d}, {w:.0f}/{wo:.0f}%)" for k, d, _, w, wo in op_rows[:10]))
    if fonts:
        top = sorted(fonts.items(), key=lambda kv: -kv[1])[:8]
        lines.append("대체된 글꼴(문서 수): " + ", ".join(f"{a}→{b} ({n})" for (a, b), n in top))
    for row in failed[:10]:
        lines.append(f"  실패: {row['key']} — {row['status']}")
    return "\n".join(lines)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--pair", nargs=2, action="append", metavar=("DOC", "PDF"), default=[], help="문서와 기준 PDF 쌍")
    parser.add_argument("--discover", action="store_true", help="pdf/·samples/ 의 PDF 이름으로 짝을 찾는다")
    parser.add_argument("--include-variants", action="store_true",
                        help="한글 2010 엔진·-kopub·-no-ttf PDF도 짝에 넣는다(기본은 뺀다. discover_pairs 주석 참조)")
    parser.add_argument("--dry-run", action="store_true", help="짝 목록만 출력하고 측정하지 않는다")
    parser.add_argument("--match", help="문서 경로에 이 문자열이 든 쌍만")
    parser.add_argument("--pages", default="1-6", help="비교할 쪽(1부터). 기본 1-6")
    parser.add_argument("--limit", type=int, help="앞에서부터 이 개수의 쌍만")
    parser.add_argument("--jobs", type=int, default=4)
    parser.add_argument("--timeout", type=int, default=180, help="쌍마다 단계별 제한 시간(초)")
    parser.add_argument("--out", type=Path, help="결과 폴더(기본: output/fidelity/<시각>)")
    parser.add_argument("--no-build", action="store_true", help="rhwp-render 를 다시 빌드하지 않는다")
    parser.add_argument("--json", action="store_true", help="쪽마다 레이어 트리 JSON 도 <결과>/<키>/json 에 저장한다(진단용)")
    args = parser.parse_args()

    pairs = [(Path(d).resolve(), Path(p).resolve()) for d, p in args.pair]
    if args.discover:
        pairs += discover_pairs(args.include_variants)
    if args.match:
        pairs = [(d, p) for d, p in pairs if args.match in str(d)]
    if args.limit:
        pairs = pairs[: args.limit]
    if not pairs:
        sys.exit("측정할 쌍이 없습니다. --pair 나 --discover 를 주세요.")
    for document, pdf in pairs:
        for path in (document, pdf):
            if not path.exists():
                sys.exit(f"파일 없음: {path}")

    if args.dry_run:
        for document, pdf in pairs:
            print(f"{document.relative_to(ROOT)}\t{pdf.relative_to(ROOT)}")
        print(f"{len(pairs)}쌍, 문서 {len({d for d, _ in pairs})}개")
        return
    if not args.no_build:
        build_tool()
    out = (args.out or ROOT / "output" / "fidelity" / datetime.datetime.now().strftime("%Y%m%d-%H%M%S")).resolve()
    out.mkdir(parents=True, exist_ok=True)
    pages = parse_pages(args.pages)
    print(f"{len(pairs)}쌍(문서 {len({d for d, _ in pairs})}개), 쪽 {args.pages}, 결과: {out}", flush=True)

    # 문서마다 한 번 그리고 그 문서의 PDF 전부와 대조한다(같은 문서가 PDF 12개와 짝지어져도 렌더는 한 번).
    by_document: dict[Path, list[Path]] = {}
    for document, pdf in pairs:
        by_document.setdefault(document, []).append(pdf)
    rows: list[dict] = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.jobs) as pool:
        futures = [pool.submit(measure_document, d, ps, out, pages, args.timeout, args.json) for d, ps in by_document.items()]
        for done, future in enumerate(concurrent.futures.as_completed(futures), 1):
            rows += future.result()
            if done % 20 == 0:
                print(f"  문서 {done}/{len(by_document)}", flush=True)
    rows.sort(key=lambda r: r["document"])
    print(write_reports(rows, out))
    print(f"TSV: {out}/summary.tsv, pages.tsv, count_docs.tsv, ops.tsv, ops_docs.tsv, fonts.tsv")


if __name__ == "__main__":
    main()
