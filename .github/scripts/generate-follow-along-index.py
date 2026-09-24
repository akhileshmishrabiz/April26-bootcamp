#!/usr/bin/env python3
"""Update the Pages landing page with every HTML document in the docs folder."""

from __future__ import annotations

import argparse
import html
import re
from html.parser import HTMLParser
from pathlib import Path

START_MARKER = "<!-- AUTO-GENERATED-DOCS:START -->"
END_MARKER = "<!-- AUTO-GENERATED-DOCS:END -->"


class TitleParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.in_title = False
        self.parts: list[str] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        if tag.lower() == "title":
            self.in_title = True

    def handle_endtag(self, tag: str) -> None:
        if tag.lower() == "title":
            self.in_title = False

    def handle_data(self, data: str) -> None:
        if self.in_title:
            self.parts.append(data)

    @property
    def title(self) -> str:
        return " ".join("".join(self.parts).split())


def document_title(path: Path) -> str:
    parser = TitleParser()
    parser.feed(path.read_text(encoding="utf-8"))
    return parser.title or path.stem.replace("-", " ").title()


def natural_key(value: str) -> list[str | int]:
    return [int(part) if part.isdigit() else part.casefold() for part in re.split(r"(\d+)", value)]


def generated_cards(docs_dir: Path) -> str:
    documents = sorted(
        (path for path in docs_dir.rglob("*.html") if path.name != "index.html"),
        key=lambda path: natural_key(path.relative_to(docs_dir).as_posix()),
    )

    cards = []
    for path in documents:
        relative_path = path.relative_to(docs_dir).as_posix()
        cards.append(
            '      <a class="card" href="{href}">\n'
            "        <strong>{title}</strong>\n"
            "        <span>{path}</span>\n"
            "      </a>".format(
                href=html.escape(relative_path, quote=True),
                title=html.escape(document_title(path)),
                path=html.escape(relative_path),
            )
        )

    return (
        f"{START_MARKER}\n"
        f"    <h2>Available lessons ({len(documents)})</h2>\n"
        '    <div class="grid">\n'
        f"{chr(10).join(cards)}\n"
        "    </div>\n"
        f"    {END_MARKER}"
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "docs_dir",
        nargs="?",
        type=Path,
        default=Path("follow-along-docs"),
    )
    args = parser.parse_args()

    index_path = args.docs_dir / "index.html"
    index = index_path.read_text(encoding="utf-8")
    replacement = generated_cards(args.docs_dir)

    marker_pattern = re.compile(
        rf"{re.escape(START_MARKER)}.*?{re.escape(END_MARKER)}",
        re.DOTALL,
    )
    if not marker_pattern.search(index):
        raise SystemExit(f"Generated-document markers are missing from {index_path}")

    index_path.write_text(marker_pattern.sub(replacement, index), encoding="utf-8")


if __name__ == "__main__":
    main()
