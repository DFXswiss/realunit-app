#!/usr/bin/env python3
"""Generate the handbook store-listing block from the Fastlane metadata.

The Fastlane metadata under ios/fastlane/metadata + android/fastlane/metadata
(and the screenshots) is the single source of truth for what ships to App
Store Connect / Play Console. The handbook section at handbook.realunit.app is
a *derived export* of those files — never hand-edited. This mirrors the
upstream/downstream relationship that docs/handbook/mails/ already has with
DFXswiss/api's mail templates.

Usage:
    scripts/assemble-handbook-store-listing.py <output-dir>

Used by:
  - Dockerfile.handbook (store-listing-builder stage → /usr/share/nginx/html/store/)
  - .github/workflows/handbook-build-check.yaml (sync gate: re-run + git diff)
  - local previews (run it, then open docs/handbook/de/index.html)

What it does:
  1. Copies the store PNGs into <out>/{ios,android}/... (the layout the
     handbook HTML links to via ../store/...).
  2. Reads the metadata .txt files. All text fields are HTML-escaped except
     the Android long description, which Google Play renders as a small HTML
     subset and is therefore run through sanitize_play_html() — an allowlist
     sanitizer — before it is interpolated unescaped into the page.
  3. Renders scripts/templates/store-listing.html.tmpl into
     <out>/store-listing.html (single-pass placeholder substitution).
  4. Substitutes the rendered block between the
     <!-- BEGIN:store-listing --> / <!-- END:store-listing --> markers in
     docs/handbook/de/index.html in place. This is what guarantees the page
     IS the export, not a separate copy. The operation is idempotent.
"""
import html
import re
import shutil
import sys
from html.parser import HTMLParser
from pathlib import Path

BEGIN = "<!-- BEGIN:store-listing -->"
END = "<!-- END:store-listing -->"

# Google Play renders only a small HTML subset in the long description. Anything
# outside this allowlist is dropped, so full_description.txt can never inject
# script or break out of its container in the handbook (where it is rendered
# unescaped to preserve the allowed formatting).
_ALLOWED_TAGS = {"b", "em", "i", "u", "strong", "br", "a", "li", "ol", "ul"}
_VOID_TAGS = {"br"}
_SAFE_URL_SCHEMES = ("http://", "https://", "mailto:")
_PLACEHOLDER = re.compile(r"\{\{ (\w+) \}\}")


class _PlayHTMLSanitizer(HTMLParser):
    """Allowlist sanitizer for the Google-Play long-description HTML subset.

    Only the allowed tags survive; every other tag is dropped (its markup is
    removed, its text kept and HTML-escaped) and all attributes are stripped
    except a scheme-validated href on <a>. The output is balanced: unclosed
    allowed tags are auto-closed and stray end tags are ignored, so the result
    cannot terminate an ancestor element (e.g. a stray </details>) or smuggle
    a <script>.
    """

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self._out = []
        self._open = []  # stack of emitted, not-yet-closed allowed tags

    def _emit_open(self, tag, attrs):
        safe_attrs = ""
        if tag == "a":
            href = next((v.strip() for k, v in attrs if k == "href" and v), None)
            if not (href and href.lower().startswith(_SAFE_URL_SCHEMES)):
                return False  # drop unsafe/empty-href links, keep their text
            safe_attrs = f' href="{html.escape(href)}" rel="nofollow noopener"'
        self._out.append(f"<{tag}{safe_attrs}>")
        self._open.append(tag)
        return True

    def handle_starttag(self, tag, attrs):
        if tag not in _ALLOWED_TAGS:
            return
        if tag in _VOID_TAGS:
            self._out.append(f"<{tag}>")
        else:
            self._emit_open(tag, attrs)

    def handle_startendtag(self, tag, attrs):
        if tag not in _ALLOWED_TAGS:
            return
        if tag in _VOID_TAGS:
            self._out.append(f"<{tag}>")
        elif self._emit_open(tag, attrs):
            self._close(tag)

    def handle_endtag(self, tag):
        if tag in _ALLOWED_TAGS and tag not in _VOID_TAGS:
            self._close(tag)

    def _close(self, tag):
        if tag not in self._open:
            return
        while self._open:
            popped = self._open.pop()
            self._out.append(f"</{popped}>")
            if popped == tag:
                break

    def handle_data(self, data):
        self._out.append(html.escape(data, quote=False))

    def result(self):
        while self._open:
            self._out.append(f"</{self._open.pop()}>")
        return "".join(self._out)


def sanitize_play_html(raw: str) -> str:
    """Reduce `raw` to the Google-Play-allowed HTML subset (safe to interpolate
    unescaped into otherwise-trusted markup)."""
    parser = _PlayHTMLSanitizer()
    parser.feed(raw)
    parser.close()
    return parser.result()


def main() -> int:
    if len(sys.argv) != 2:
        print(f"usage: {sys.argv[0]} <output-dir>", file=sys.stderr)
        return 2

    repo = Path(__file__).resolve().parent.parent
    out = Path(sys.argv[1])
    ios = repo / "ios/fastlane/metadata/de-DE"
    android = repo / "android/fastlane/metadata/android/de-DE"

    # 1) Copy PNGs into <out>/{ios,android}/...
    mappings = [
        (repo / "ios/fastlane/screenshots/de-DE/iPhone 6.9 Display", out / "ios/iphone-69"),
        (repo / "ios/fastlane/screenshots/de-DE/iPad Pro (13 inch) Display", out / "ios/ipad-13"),
        (android / "images/phoneScreenshots", out / "android/phone"),
        (android / "images/sevenInchScreenshots", out / "android/seven-inch"),
        (android / "images/tenInchScreenshots", out / "android/ten-inch"),
    ]
    for src, dst in mappings:
        if not src.is_dir():
            print(f"error: screenshot source missing: {src}", file=sys.stderr)
            return 1
        dst.mkdir(parents=True, exist_ok=True)
        for png in sorted(src.glob("*.png")):
            shutil.copy2(png, dst / png.name)

    (out / "android").mkdir(parents=True, exist_ok=True)
    shutil.copy2(android / "images/featureGraphic.png", out / "android/featureGraphic.png")
    shutil.copy2(android / "images/icon.png", out / "android/icon.png")

    # 2) Read text content (UTF-8 safe)
    def read(p: Path) -> str:
        return p.read_text(encoding="utf-8").strip()

    ctx = {
        "ios_name": html.escape(read(ios / "name.txt")),
        "ios_subtitle": html.escape(read(ios / "subtitle.txt")),
        "ios_promotional_text": html.escape(read(ios / "promotional_text.txt")),
        "ios_description": html.escape(read(ios / "description.txt")),
        "ios_keywords": html.escape(read(ios / "keywords.txt")),
        "ios_marketing_url": html.escape(read(ios / "marketing_url.txt")),
        "ios_privacy_url": html.escape(read(ios / "privacy_url.txt")),
        "ios_support_url": html.escape(read(ios / "support_url.txt")),
        "ios_copyright": html.escape(read(ios / "copyright.txt")),
        "ios_release_notes": html.escape(read(ios / "release_notes.txt")),
        "android_title": html.escape(read(android / "title.txt")),
        "android_short": html.escape(read(android / "short_description.txt")),
        # Google Play allows a small HTML subset here; sanitize to that allowlist
        # rather than escaping, so the formatting renders but nothing can break out.
        "android_full_html": sanitize_play_html(read(android / "full_description.txt")),
        "android_changelog": html.escape(read(android / "changelogs/default.txt")),
    }

    # 3) Render the block from the template — single pass, each placeholder
    #    resolved exactly once (a substituted value is never re-scanned).
    template = Path(__file__).parent / "templates/store-listing.html.tmpl"
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
    (out / "store-listing.html").write_text(rendered + "\n", encoding="utf-8")

    # 4) Substitute the block in docs/handbook/de/index.html in place (idempotent)
    index = repo / "docs/handbook/de/index.html"
    content = index.read_text(encoding="utf-8")
    if BEGIN not in content or END not in content:
        print(
            f"error: {index} is missing the {BEGIN} / {END} markers — add them once "
            "(see the scope-extension comment on issue #634) before running this script.",
            file=sys.stderr,
        )
        return 1
    b = content.index(BEGIN)
    e = content.index(END) + len(END)
    new = content[:b] + BEGIN + "\n" + rendered + "\n" + END + content[e:]
    index.write_text(new, encoding="utf-8")

    pngs = sum(1 for _ in out.rglob("*.png"))
    print(f"rendered store-listing block + {pngs} PNGs into {out}; synced {index}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
