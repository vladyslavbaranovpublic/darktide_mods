#!/usr/bin/env python3
"""
Translate and format RitualZones localization entries.

Usage examples:
  python translate_localization.py --lang all
  python translate_localization.py --lang fr,ja
  python translate_localization.py --format-only
  python translate_localization.py --lang de --overwrite

Notes:
  - Requires: pip install deep-translator
  - By default, only missing language entries are filled.
  - Placeholders and tags ({#color}, \\xNN, \\n, % tokens) are preserved.
"""

import argparse
import re
from typing import Dict, List, Tuple

LANG_ORDER = [
    "en",
    "fr",
    "de",
    "es",
    "it",
    "ru",
    "pt-br",
    "zh-cn",
    "zh-tw",
    "ja",
    "ko",
    "pl",
]

LANG_CODES = {
    "fr": "fr",
    "de": "de",
    "es": "es",
    "it": "it",
    "ru": "ru",
    "pt-br": "pt",
    "zh-cn": "zh-CN",
    "zh-tw": "zh-TW",
    "ja": "ja",
    "ko": "ko",
    "pl": "pl",
}

LANG_LINE_RE = re.compile(
    r'^\s*(?P<lang>(?:[a-z]{2}|[a-z]{2}-[a-z]{2})|\["[a-z-]+"\])\s*=\s*"(?P<text>(?:\\.|[^"\\])*)"(?P<suffix>\s*,\s*)$'
)
ENTRY_START_RE = re.compile(r'^(?P<indent>\s*)(?P<key>[A-Za-z0-9_]+|\["[^"]+"\])\s*=\s*\{\s*$')


def brace_delta(line: str) -> int:
    delta = 0
    in_string = False
    escaped = False
    for ch in line:
        if in_string:
            if escaped:
                escaped = False
                continue
            if ch == "\\":
                escaped = True
                continue
            if ch == "\"":
                in_string = False
                continue
        else:
            if ch == "\"":
                in_string = True
                continue
            if ch == "{":
                delta += 1
            elif ch == "}":
                delta -= 1
    return delta


def mask_tokens(text: str) -> Tuple[str, List[Tuple[str, str]]]:
    tokens: List[Tuple[str, str]] = []

    def repl(match: re.Match) -> str:
        token = match.group(0)
        placeholder = f"__PH{len(tokens)}__"
        tokens.append((placeholder, token))
        return placeholder

    text = re.sub(r"\{#[^}]+\}", repl, text)
    text = re.sub(r"\\x[0-9A-Fa-f]{2}", repl, text)
    text = re.sub(r"[\ue000-\uf8ff]", repl, text)
    text = re.sub(r"\\n", repl, text)
    text = re.sub(r"%[%\w\.]+", repl, text)
    return text, tokens


def unmask_tokens(text: str, tokens: List[Tuple[str, str]]) -> str:
    for placeholder, token in tokens:
        text = text.replace(placeholder, token)
    return text


def normalize_text(text: str) -> str:
    replacements = {
        "\u00a0": " ",
        "\u200b": "",
        "\u201c": "\"",
        "\u201d": "\"",
        "\u201e": "\"",
        "\u201f": "\"",
        "\u2018": "'",
        "\u2019": "'",
        "\u2039": "\"",
        "\u203a": "\"",
        "\u00ab": "\"",
        "\u00bb": "\"",
    }
    for src, dst in replacements.items():
        text = text.replace(src, dst)
    return text


def escape_quotes(text: str) -> str:
    escaped = False
    out = []
    for ch in text:
        if escaped:
            out.append(ch)
            escaped = False
            continue
        if ch == "\\":
            out.append(ch)
            escaped = True
            continue
        if ch == "\"":
            out.append("\\\"")
            continue
        out.append(ch)
    return "".join(out)


def needs_translation(text: str) -> bool:
    stripped = re.sub(r"\{#[^}]+\}", "", text)
    stripped = re.sub(r"\\x[0-9A-Fa-f]{2}", "", stripped)
    stripped = stripped.replace("\\n", " ")
    stripped = re.sub(r"%[%\w\.]+", "", stripped)
    stripped = re.sub(r"[\W_]+", "", stripped)
    return bool(stripped)


def parse_localization(lines: List[str]):
    start_idx = None
    end_idx = None
    loc_depth = 0
    loc_started = False
    entries = []

    i = 0
    while i < len(lines):
        line = lines[i]
        if not loc_started:
            if re.search(r"^\s*local\s+localization\s*=\s*\{", line):
                loc_started = True
                start_idx = i
                loc_depth += brace_delta(line)
            i += 1
            continue

        if loc_started:
            if loc_depth == 1:
                m = ENTRY_START_RE.match(line)
                if m:
                    indent = m.group("indent")
                    raw_key = m.group("key")
                    loc_depth += brace_delta(line)
                    entry_depth = loc_depth
                    entry_lines = [line]
                    i += 1
                    while i < len(lines):
                        entry_line = lines[i]
                        entry_lines.append(entry_line)
                        loc_depth += brace_delta(entry_line)
                        i += 1
                        if loc_depth < entry_depth:
                            break
                    lang_map: Dict[str, str] = {}
                    extra_lines: List[str] = []
                    for inner in entry_lines[1:-1]:
                        m_lang = LANG_LINE_RE.match(inner)
                        if m_lang:
                            lang_raw = m_lang.group("lang")
                            lang = lang_raw[2:-2] if lang_raw.startswith('["') else lang_raw
                            lang_map[lang] = m_lang.group("text")
                        else:
                            if inner.strip():
                                extra_lines.append(inner)
                    entries.append(
                        {
                            "indent": indent,
                            "key": raw_key,
                            "langs": lang_map,
                            "extra": extra_lines,
                        }
                    )
                    continue

            loc_depth += brace_delta(line)
            if loc_depth == 0:
                end_idx = i
                break
        i += 1

    return start_idx, end_idx, entries


def translate_entries(entries, languages, overwrite):
    try:
        from deep_translator import GoogleTranslator
    except Exception as exc:
        raise RuntimeError("deep-translator is required: pip install deep-translator") from exc

    for lang in languages:
        if lang == "en":
            continue
        if lang not in LANG_CODES:
            raise ValueError(f"Unsupported language: {lang}")
        translator = GoogleTranslator(source="en", target=LANG_CODES[lang])

        items = []
        for entry in entries:
            en_text = entry["langs"].get("en")
            if not en_text:
                continue
            if not overwrite and lang in entry["langs"]:
                continue
            if not needs_translation(en_text):
                entry["langs"][lang] = en_text
                continue
            masked, tokens = mask_tokens(en_text)
            items.append((entry, masked, tokens))

        batch = []
        batch_meta = []
        for entry, masked, tokens in items:
            batch.append(masked)
            batch_meta.append((entry, tokens))
            if len(batch) >= 25:
                results = translator.translate_batch(batch)
                for (entry_ref, tokens_ref), translated in zip(batch_meta, results):
                    restored = escape_quotes(normalize_text(unmask_tokens(translated, tokens_ref)))
                    entry_ref["langs"][lang] = restored
                batch = []
                batch_meta = []

        if batch:
            results = translator.translate_batch(batch)
            for (entry_ref, tokens_ref), translated in zip(batch_meta, results):
                restored = escape_quotes(normalize_text(unmask_tokens(translated, tokens_ref)))
                entry_ref["langs"][lang] = restored


def format_entries(entries):
    formatted = []
    for entry in entries:
        indent = entry["indent"]
        formatted.append(f"{indent}{entry['key']} = {{")
        for lang in LANG_ORDER:
            if lang in entry["langs"]:
                lang_key = f'["{lang}"]' if "-" in lang else lang
                formatted.append(f'{indent}\t{lang_key} = "{entry["langs"][lang]}",')
        for extra in entry["extra"]:
            formatted.append(extra)
        formatted.append(f"{indent}}},")
    return formatted


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--file",
        default="RitualZones_localization.lua",
        help="Path to localization file",
    )
    parser.add_argument(
        "--lang",
        default="all",
        help="Comma-separated languages to translate (e.g. fr,ja) or 'all'",
    )
    parser.add_argument("--format-only", action="store_true", help="Only format, no translation")
    parser.add_argument("--overwrite", action="store_true", help="Overwrite existing translations")
    args = parser.parse_args()

    with open(args.file, "r", encoding="utf-8") as f:
        lines = f.read().splitlines()

    start_idx, end_idx, entries = parse_localization(lines)
    if start_idx is None or end_idx is None:
        raise RuntimeError("Could not find localization table in file.")

    if not args.format_only:
        if args.lang == "all":
            languages = LANG_ORDER
        else:
            languages = [lang.strip() for lang in args.lang.split(",") if lang.strip()]
        translate_entries(entries, languages, args.overwrite)

    formatted_entries = format_entries(entries)
    out_lines = []
    out_lines.extend(lines[: start_idx + 1])
    out_lines.extend(formatted_entries)
    out_lines.append(lines[end_idx])
    out_lines.extend(lines[end_idx + 1 :])

    with open(args.file, "w", encoding="utf-8") as f:
        f.write("\n".join(out_lines) + "\n")

    print("Localization updated:", args.file)


if __name__ == "__main__":
    main()
