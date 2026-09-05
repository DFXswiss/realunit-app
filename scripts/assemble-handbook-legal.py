#!/usr/bin/env python3
"""Generate the handbook legal-downloads block from the in-app legal Markdown.

The Markdown under assets/legal/ is the single source of truth for the
RealUnit documents that the app renders in-app (LegalDocumentPage and the
referral terms page read assets/legal/<base>_<lang>.md via rootBundle). The
handbook section at
handbook.realunit.app is a *derived export* of those files — never hand-edited.
This mirrors the upstream/downstream relationship that the store-listing and
mails/ sections already have.

Usage:
    scripts/assemble-handbook-legal.py <output-dir>

Used by:
  - Dockerfile.handbook (legal-docs-builder stage → rewrites docs/handbook/de/
    index.html; the PDF/DOCX binaries are produced separately by
    scripts/build-legal-downloads.sh — see the determinism note below)
  - .github/workflows/handbook-build-check.yaml (sync gate: re-run + git diff)
  - local previews (run it, then open docs/handbook/de/index.html)

What it does:
  1. Discovers the document set: for each base in BASES, globs
     assets/legal/<base>_*.md to find the available languages. Errors out if a
     base has zero languages.
  2. Resolves each document's title from assets/languages/strings_<lang>.arb
     (the mapped ARB key per base, see TITLE_KEYS) so the handbook titles stay
     in lockstep with the in-app titles. Falls back to the `de` title if a
     language's ARB lacks the key.
  3. Renders scripts/templates/legal-downloads.html.tmpl into
     <out>/legal-downloads.html and substitutes the rendered block between the
     <!-- BEGIN:legal-downloads --> / <!-- END:legal-downloads --> markers in
     docs/handbook/de/index.html in place (idempotent).

What it deliberately does NOT do:
  - It does NOT invoke pandoc and does NOT emit any PDF/DOCX. Those binaries are
    non-deterministic (embedded timestamps, tool-version metadata) and are
    produced only inside the image by scripts/build-legal-downloads.sh, git-
    ignored like the screenshots. Keeping pandoc out of this script is what lets
    the rendered HTML block be deterministic and therefore sync-gateable.

  Every value interpolated into the HTML (titles from ARB, discovered language
  codes) is HTML-escaped; the document bases are a fixed allowlist (BASES).
"""
import html
import re
import sys
from pathlib import Path

BEGIN = "<!-- BEGIN:legal-downloads -->"
END = "<!-- END:legal-downloads -->"

# In-app documents rendered from repo-local Markdown. DFX, Aktionariat and the
# externally-hosted corporate PDFs are out of scope — they have no Markdown
# source in the repo and cannot be a derived export.
BASES = [
    "privacy_policy",
    "terms_of_use",
    "registration_agreement",
    "referral_terms",
]

# Maps each document base to the ARB key the app uses for its title, so the
# handbook label matches what the user sees in-app.
TITLE_KEYS = {
    "privacy_policy": "legalDisclaimerCheckboxPrivacyPolicy",
    "terms_of_use": "termsOfUse",
    "registration_agreement": "legalDisclaimerCheckboxRegistrationAgreement",
    "referral_terms": "referralTermsTitle",
}

# Languages are discovered, never hardcoded; this only validates that a token
# extracted from a filename looks like a language code before it is used in an
# id / href / download path.
_LANG_RE = re.compile(r"^[a-z0-9-]+$")
_PLACEHOLDER = re.compile(r"\{\{ (\w+) \}\}")

REPO = "https://github.com/RealUnitCH/app"


def _esc(value: str) -> str:
    """HTML-escape a value for safe interpolation into text or an attribute."""
    return html.escape(value, quote=True)


def load_arb(repo: Path, lang: str) -> dict:
    """Load assets/languages/strings_<lang>.arb (JSON). Errors if missing."""
    import json

    path = repo / "assets/languages" / f"strings_{lang}.arb"
    if not path.is_file():
        raise SystemExit(f"error: ARB file missing for discovered language '{lang}': {path}")
    return json.loads(path.read_text(encoding="utf-8"))


def discover(repo: Path) -> "dict[str, list[str]]":
    """For each base, glob assets/legal/<base>_*.md → sorted language list."""
    legal = repo / "assets/legal"
    result = {}
    for base in BASES:
        langs = []
        for md in legal.glob(f"{base}_*.md"):
            lang = md.name[len(base) + 1 : -len(".md")]
            if not _LANG_RE.match(lang):
                raise SystemExit(f"error: unexpected language token '{lang}' from {md.name}")
            langs.append(lang)
        if not langs:
            raise SystemExit(f"error: no source Markdown found for '{base}' (assets/legal/{base}_*.md)")
        result[base] = sorted(langs)
    return result


def render_rows(doc_langs: "dict[str, list[str]]", titles: "dict[str, dict[str, str]]") -> str:
    """Build the per-(base, lang) download cards. Deterministic ordering:
    BASES order, then languages sorted alphabetically."""
    parts = []
    for base in BASES:
        de_title = _esc(titles[base]["de"])
        parts.append(
            f'  <h3>{de_title} '
            f'<a class="src" href="{REPO}/tree/develop/assets/legal" '
            f'title="Quelle: assets/legal/">↗</a></h3>'
        )
        parts.append('  <div class="tests cols-2">')
        for lang in doc_langs[base]:
            anchor = f"legal-{base}-{lang}"
            stem = f"{base}_{lang}"
            title = _esc(titles[base][lang])
            lang_e = _esc(lang)
            parts.append(
                f'    <div class="test legal-doc" id="{_esc(anchor)}">\n'
                f'      <div class="head">\n'
                f'        <a class="name permalink" href="#{_esc(anchor)}">{_esc(stem)}</a>\n'
                f'        <button class="copy-link" type="button" data-target="{_esc(anchor)}" '
                f'title="Direkt-Link kopieren" aria-label="Direkt-Link kopieren">🔗 Link</button>\n'
                f'        <span class="src">{lang_e}</span>\n'
                f'      </div>\n'
                f'      <div class="downloads">\n'
                f'        <span class="doc-title">{title}</span>\n'
                f'        <a class="dl-btn" href="../legal/{_esc(stem)}.pdf" download>PDF</a>\n'
                f'        <a class="dl-btn" href="../legal/{_esc(stem)}.docx" download>DOCX</a>\n'
                f'        <a class="src" href="{REPO}/blob/develop/assets/legal/{_esc(stem)}.md" '
                f'title="Quelle: {_esc(stem)}.md">Markdown ↗</a>\n'
                f'      </div>\n'
                f'    </div>'
            )
        parts.append('  </div>')
    return "\n".join(parts)


def main() -> int:
    if len(sys.argv) != 2:
        print(f"usage: {sys.argv[0]} <output-dir>", file=sys.stderr)
        return 2

    repo = Path(__file__).resolve().parent.parent
    out = Path(sys.argv[1])

    # 1) Discover documents + languages from the filesystem (never hardcoded).
    doc_langs = discover(repo)

    # 2) Resolve titles from the ARB files, falling back to `de`. Every document
    #    must have a `de` source, since `de` is the per-document title and
    #    heading fallback language (render_rows() uses titles[base]["de"]).
    for base in BASES:
        if "de" not in doc_langs[base]:
            raise SystemExit(
                f"error: '{base}' has no `de` document (assets/legal/{base}_de.md) — "
                "`de` is the per-document title/heading fallback language"
            )
    all_langs = sorted({lang for langs in doc_langs.values() for lang in langs})
    arbs = {lang: load_arb(repo, lang) for lang in all_langs}
    titles = {}
    for base in BASES:
        key = TITLE_KEYS[base]
        de_title = arbs["de"].get(key)
        if not de_title:
            raise SystemExit(f"error: ARB key '{key}' (for '{base}') missing from strings_de.arb")
        titles[base] = {}
        for lang in doc_langs[base]:
            titles[base][lang] = arbs[lang].get(key) or de_title

    # 3) Render the block from the template (single pass: each placeholder
    #    resolved exactly once, a substituted value is never re-scanned).
    template = Path(__file__).parent / "templates/legal-downloads.html.tmpl"
    ctx = {"rows": render_rows(doc_langs, titles)}
    unknown = []

    def substitute(match):
        key = match.group(1)
        if key not in ctx:
            unknown.append(key)
            return match.group(0)
        return ctx[key]

    rendered = _PLACEHOLDER.sub(substitute, template.read_text(encoding="utf-8").strip("\n"))
    if unknown:
        print(f"error: unknown template placeholder(s): {sorted(set(unknown))}", file=sys.stderr)
        return 1

    out.mkdir(parents=True, exist_ok=True)
    (out / "legal-downloads.html").write_text(rendered + "\n", encoding="utf-8")

    # 4) Substitute the block in docs/handbook/de/index.html in place (idempotent).
    index = repo / "docs/handbook/de/index.html"
    content = index.read_text(encoding="utf-8")
    if BEGIN not in content or END not in content:
        print(
            f"error: {index} is missing the {BEGIN} / {END} markers — add them once "
            "(see issue #658) before running this script.",
            file=sys.stderr,
        )
        return 1
    b = content.index(BEGIN)
    e = content.index(END) + len(END)
    new = content[:b] + BEGIN + "\n" + rendered + "\n" + END + content[e:]
    index.write_text(new, encoding="utf-8")

    n = sum(len(v) for v in doc_langs.values())
    print(f"rendered legal-downloads block ({n} sources across {len(BASES)} docs) into {out}; synced {index}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
