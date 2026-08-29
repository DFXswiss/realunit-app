#!/usr/bin/env bash
#
# Build the downloadable PDF + DOCX of the in-app legal documents from their
# Markdown sources under assets/legal/, into <output-dir>/legal/.
#
# Usage:
#   scripts/build-legal-downloads.sh <output-dir>
#
# Run ONLY inside the handbook image's legal-docs-builder stage (needs pandoc +
# weasyprint). The output is intentionally NON-deterministic — pandoc embeds
# timestamps and tool-version metadata — so it is treated like the assembled
# screenshots: generated only in the image, git-ignored, never committed, and
# never sync-gated. The deterministic HTML block (the download links) is the
# separate concern of scripts/assemble-handbook-legal.py.
#
# weasyprint is used as the PDF engine (HTML/CSS based) deliberately, to avoid
# pulling a full TeX Live into the image just for PDF rendering.
#
# Document discovery mirrors assemble-handbook-legal.py: the same bases,
# languages discovered by glob (never hardcoded). Keep this list in lockstep
# with BASES in assemble-handbook-legal.py.
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "usage: $0 <output-dir>" >&2
  exit 2
fi

out="$1"
# Resolve the repo root from this script's location (scripts/..), so the script
# works regardless of the caller's working directory.
script_dir="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$script_dir/.." && pwd)"
legal_src="$repo/assets/legal"
legal_out="$out/legal"

bases="privacy_policy terms_of_use registration_agreement referral_terms"

mkdir -p "$legal_out"

count=0
for base in $bases; do
  found=0
  for md in "$legal_src/$base"_*.md; do
    # Guard against a literal no-match glob.
    [ -e "$md" ] || continue
    found=1
    stem="$(basename "$md" .md)"
    pandoc "$md" -o "$legal_out/$stem.docx"
    pandoc "$md" --pdf-engine=weasyprint -o "$legal_out/$stem.pdf"
    count=$((count + 2))
  done
  if [ "$found" -eq 0 ]; then
    echo "error: no source Markdown found for '$base' ($legal_src/${base}_*.md)" >&2
    exit 1
  fi
done

echo "built $count legal download files into $legal_out"
