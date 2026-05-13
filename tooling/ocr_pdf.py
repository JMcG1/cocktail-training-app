from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
from pathlib import Path


COMMON_TESSERACT_PATHS = [
    Path(r"C:\Program Files\Tesseract-OCR\tesseract.exe"),
    Path(r"C:\Program Files (x86)\Tesseract-OCR\tesseract.exe"),
]

COMMON_POPPLER_PATHS = [
    Path(r"C:\Program Files\poppler\Library\bin\pdftoppm.exe"),
    Path(r"C:\Program Files\poppler\bin\pdftoppm.exe"),
]


def find_executable(name: str, common_paths: list[Path]) -> Path | None:
    from_path = shutil.which(name)
    if from_path:
      return Path(from_path)
    for candidate in common_paths:
      if candidate.exists():
        return candidate
    return None


def run(command: list[str], *, cwd: Path | None = None) -> None:
    completed = subprocess.run(
        command,
        cwd=str(cwd) if cwd else None,
        capture_output=True,
        text=True,
    )
    if completed.returncode != 0:
        print(completed.stdout)
        print(completed.stderr, file=sys.stderr)
        raise RuntimeError(f"Command failed: {' '.join(command)}")


def render_pdf_pages(
    pdf_path: Path,
    output_dir: Path,
    pdftoppm_path: Path,
    dpi: int,
) -> list[Path]:
    prefix = output_dir / "page"
    command = [
        str(pdftoppm_path),
        "-png",
        "-r",
        str(dpi),
        str(pdf_path),
        str(prefix),
    ]
    run(command)
    images = sorted(output_dir.glob("page-*.png"))
    if not images:
        raise RuntimeError("No page images were generated from the PDF.")
    return images


def ocr_page(
    image_path: Path,
    tesseract_path: Path,
    output_base: Path,
    psm: int,
    language: str,
) -> Path:
    command = [
        str(tesseract_path),
        str(image_path),
        str(output_base),
        "--psm",
        str(psm),
        "-l",
        language,
    ]
    run(command)
    txt_path = output_base.with_suffix(".txt")
    if not txt_path.exists():
        raise RuntimeError(f"OCR output missing for {image_path.name}")
    return txt_path


def combine_text_files(text_files: list[Path], combined_output: Path) -> None:
    chunks: list[str] = []
    for index, txt_path in enumerate(text_files, start=1):
        text = txt_path.read_text(encoding="utf-8", errors="ignore").strip()
        chunks.append(f"===== PAGE {index} =====\n{text}\n")
    combined_output.write_text("\n".join(chunks), encoding="utf-8")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Render a scanned cocktail-spec PDF into page images and OCR text files.",
    )
    parser.add_argument("pdf", help="Absolute path to the source PDF.")
    parser.add_argument(
        "--output-dir",
        default="ocr_output",
        help="Directory where page images and OCR text files will be written.",
    )
    parser.add_argument(
        "--dpi",
        type=int,
        default=300,
        help="Render DPI for PDF page images. Higher values can improve OCR quality.",
    )
    parser.add_argument(
        "--psm",
        type=int,
        default=6,
        help="Tesseract page segmentation mode. 6 works well for block-style spec layouts.",
    )
    parser.add_argument(
        "--language",
        default="eng",
        help="Tesseract language code. Default is eng.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    pdf_path = Path(args.pdf).expanduser().resolve()
    if not pdf_path.exists():
        print(f"PDF not found: {pdf_path}", file=sys.stderr)
        return 1

    tesseract_path = find_executable("tesseract", COMMON_TESSERACT_PATHS)
    if not tesseract_path:
        print(
            "Tesseract OCR was not found. Install Tesseract and make sure tesseract.exe is on PATH.",
            file=sys.stderr,
        )
        return 1

    pdftoppm_path = find_executable("pdftoppm", COMMON_POPPLER_PATHS)
    if not pdftoppm_path:
        print(
            "Poppler's pdftoppm was not found. Install Poppler for Windows and add pdftoppm.exe to PATH.",
            file=sys.stderr,
        )
        return 1

    output_dir = Path(args.output_dir).expanduser().resolve()
    output_dir.mkdir(parents=True, exist_ok=True)

    print(f"Rendering PDF pages from: {pdf_path}")
    print(f"Using pdftoppm: {pdftoppm_path}")
    print(f"Using tesseract: {tesseract_path}")

    images = render_pdf_pages(pdf_path, output_dir, pdftoppm_path, args.dpi)
    print(f"Generated {len(images)} page image(s).")

    text_files: list[Path] = []
    for image in images:
        page_name = image.stem
        output_base = output_dir / page_name
        txt_path = ocr_page(
            image,
            tesseract_path,
            output_base,
            args.psm,
            args.language,
        )
        text_files.append(txt_path)
        print(f"OCR complete: {txt_path.name}")

    combined_output = output_dir / f"{pdf_path.stem}.ocr.txt"
    combine_text_files(text_files, combined_output)
    print(f"Combined OCR text written to: {combined_output}")
    print("Next step: import this OCR text file in the app or parse it with tooling/parse_ocr_text.dart.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
