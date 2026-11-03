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

주의
- 90% 미만은 "새 회귀 시험·기준 파일을 추가하지 않는다"는 게이트이지 이 도구의 실패가 아니다(AGENTS.md 시각 검증).
- 현재 일치율은 한컴 글꼴이 이 Mac에 없어 글꼴 대체가 지배적이다. `fonts.tsv`가 어떤 글꼴이 무엇으로 대체됐는지 센다.
- 쪽수가 한컴 PDF와 다르면 점수와 별개로 `count_match=0`으로 기록한다(두 쪽수의 공통 쪽만 비교한다).
- 산출물(PNG·TSV)은 기본적으로 git 이 무시하는 `output/fidelity/` 아래에 만든다. 커밋하지 않는다.
"""
import argparse
import concurrent.futures
import datetime
import re
import statistics
import subprocess
import sys
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


def discover_pairs() -> list[tuple[Path, Path]]:
    """`pdf/`·`samples/`의 PDF 이름에서 짝 문서를 찾는다: `<이름>-20NN.pdf` ↔ `samples/**/<이름>.hwp|hwpx|hwp3`.

    `<이름>-hwp-2020.pdf`처럼 형식 접미사가 붙은 것은 같은 형식의 문서를 고른다. 이름 기반 추정이라 완벽하지 않으므로
    쪽수 불일치(`count_match=0`)가 잘못된 짝의 신호가 된다.
    """
    documents: dict[str, list[Path]] = {}
    for extension in ("hwp", "hwpx", "hwp3"):
        for path in (ROOT / "samples").rglob(f"*.{extension}"):
            documents.setdefault(path.stem, []).append(path)
    pairs = []
    for pdf in sorted(list((ROOT / "pdf").glob("*.pdf")) + list((ROOT / "samples").glob("*.pdf"))):
        stem = re.sub(r"-(20\d\d)$", "", pdf.stem)
        wanted_extension = None
        if stem.endswith("-hwpx"):
            stem, wanted_extension = stem[: -len("-hwpx")], "hwpx"
        elif stem.endswith("-hwp"):
            stem, wanted_extension = stem[: -len("-hwp")], "hwp"
        candidates = documents.get(stem, [])
        if wanted_extension:
            candidates = [p for p in candidates if p.suffix == f".{wanted_extension}"]
        if candidates:
            pairs.append((sorted(candidates)[0], pdf))
    return pairs


def safe_key(pdf: Path) -> str:
    """결과 폴더 이름. 같은 문서가 여러 기준 PDF(2020·2024 등)와 짝지어지고 같은 이름의 문서가 폴더만 달리 있을 수 있어
    PDF 의 저장소 상대 경로로 정한다(이름만 쓰면 서로의 결과를 덮어쓴다)."""
    relative = pdf.relative_to(ROOT).with_suffix("")
    return re.sub(r"[^0-9A-Za-z가-힣_.-]+", "_", str(relative))[:120]


def run(command: list[str], timeout: int) -> subprocess.CompletedProcess:
    return subprocess.run(command, capture_output=True, text=True, timeout=timeout)


def total_pages(output: str) -> int | None:
    match = re.search(r"총 (\d+)쪽", output)
    return int(match.group(1)) if match else None


def measure(document: Path, pdf: Path, out: Path, pages: list[int], timeout: int, dump_json: bool = False) -> dict:
    """한 쌍을 측정한다. 실패해도 예외를 던지지 않고 status 에 사유를 담는다."""
    key = safe_key(pdf)
    folder = out / key
    rhwp_dir, pdf_dir = folder / "rhwp", folder / "pdf"
    row = {"key": key, "document": str(document.relative_to(ROOT)), "pdf": str(pdf.relative_to(ROOT)),
           "rhwp_total": None, "pdf_total": None, "count_match": None, "pages": [], "fonts": {}, "skipped": {}, "status": ""}
    selection = ",".join(str(p) for p in pages)
    try:
        command = [str(RENDER), str(document), "--all", str(rhwp_dir), "--pages", selection, "--scale", "1"]
        if dump_json:
            command += ["--json", str(folder / "json")]
        rendered = run(command, timeout)
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


def write_reports(rows: list[dict], out: Path) -> str:
    """쪽별·문서별 TSV 와 글꼴 집계를 쓰고 사람이 읽을 요약을 돌려준다."""
    with (out / "pages.tsv").open("w", encoding="utf-8") as stream:
        stream.write("key\tpage\tmatch_percent\tbelow_90\n")
        for row in rows:
            for page, percent in row["pages"]:
                stream.write(f"{row['key']}\t{page}\t{percent:.3f}\t{int(percent < GATE)}\n")

    with (out / "summary.tsv").open("w", encoding="utf-8") as stream:
        stream.write("key\tdocument\tpdf\trhwp_total\tpdf_total\tcount_match\tcompared\tmin\tmean\tbelow_90\tstatus\n")
        for row in rows:
            values = [percent for _, percent in row["pages"]]
            stream.write("\t".join(str(x) for x in [
                row["key"], row["document"], row["pdf"], row["rhwp_total"], row["pdf_total"], row["count_match"],
                len(values), f"{min(values):.3f}" if values else "", f"{statistics.mean(values):.3f}" if values else "",
                sum(v < GATE for v in values), row["status"],
            ]) + "\n")

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
    lines = [
        f"문서 {len(rows)}개 (측정 {len(scored)}, 실패 {len(failed)}), 쪽수 불일치 {len(mismatched)}개",
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
        pairs += discover_pairs()
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

    if not args.no_build:
        build_tool()
    out = (args.out or ROOT / "output" / "fidelity" / datetime.datetime.now().strftime("%Y%m%d-%H%M%S")).resolve()
    out.mkdir(parents=True, exist_ok=True)
    pages = parse_pages(args.pages)
    print(f"{len(pairs)}쌍, 쪽 {args.pages}, 결과: {out}", flush=True)

    rows: list[dict] = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.jobs) as pool:
        futures = [pool.submit(measure, d, p, out, pages, args.timeout, args.json) for d, p in pairs]
        for done, future in enumerate(concurrent.futures.as_completed(futures), 1):
            rows.append(future.result())
            if done % 10 == 0:
                print(f"  {done}/{len(pairs)}", flush=True)
    rows.sort(key=lambda r: r["document"])
    print(write_reports(rows, out))
    print(f"TSV: {out}/summary.tsv, pages.tsv, ops.tsv, ops_docs.tsv, fonts.tsv")


if __name__ == "__main__":
    main()
