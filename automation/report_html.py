"""Turns the plain-text triage-cards report into an HTML email.

The report format is the one in skills/triage-cards/SKILL.md: status lines (an icon and text),
section headings like "Shipped to Prod (2)", and card lines like
"✅ #12 Title (https://...): note". Lines it doesn't recognise are kept as plain paragraphs, so a
report that drifts from the format still reads fine. Inline styles only: most mail clients drop
<style> blocks. Change the colors in C to match your brand.
"""
import re
from datetime import datetime
from html import escape

C = {
    "page": "#F6F7F9", "card": "#FFFFFF", "header": "#1F2937", "accent": "#A3E635",
    "ink": "#111827", "muted": "#6B7280", "ring": "#D1D5DB", "link": "#1D4ED8",
}
FONT = "-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif"
TONE = {  # icon: (text color, background)
    "✅": ("#15803D", "#ECFDF3"),
    "⚠️": ("#9A6700", "#FFF6DB"),
    "⚠": ("#9A6700", "#FFF6DB"),
    "❌": ("#B91C1C", "#FDECEC"),
}
CARD_RE = re.compile(r"^#(\d+)\s+(.*?)\s+\((https?://[^)\s]+)\):?\s*(.*)$", re.S)
SECTION_RE = re.compile(r"^([A-Z][^:]*?)\s+\((\d+)\)$")
URL_RE = re.compile(r"(https?://[^\s)]+)")


def esc(s):
    return escape(s, quote=True)


def linkify(s):
    parts = URL_RE.split(s)
    return "".join(
        f'<a href="{esc(p)}" style="color:{C["link"]}">{esc(p)}</a>' if i % 2 else esc(p)
        for i, p in enumerate(parts)
    )


def split_icon(line):
    for icon in TONE:
        if line.startswith(icon):
            return icon, line[len(icon):].strip()
    return None


def parse_report(text):
    blocks, section = [], None
    for raw in text.splitlines():
        line = raw.strip()
        if not line:
            continue
        iconed = split_icon(line)
        sec = SECTION_RE.match(line)
        if sec and not iconed:
            section = {"type": "section", "title": sec[1], "count": sec[2], "items": []}
            blocks.append(section)
            continue
        if iconed:
            icon, rest = iconed
            card = CARD_RE.match(rest)
            if card and section is not None:
                section["items"].append(
                    {"icon": icon, "num": card[1], "title": card[2], "url": card[3], "note": card[4]}
                )
                continue
            # A status line (Nothing to do, a failure, Repo state) ends the section it follows.
            section = None
            blocks.append({"type": "status", "icon": icon, "text": rest})
            continue
        if section is not None and section["items"]:
            # A wrapped continuation of the previous card's note.
            last = section["items"][-1]
            last["note"] = f'{last["note"]} {line}'.strip()
            continue
        section = None
        blocks.append({"type": "text", "text": line})
    return blocks


def status_html(b):
    fg, bg = TONE[b["icon"]]
    # A failure about a card links its number and title instead of showing the raw card URL.
    card = CARD_RE.match(b["text"])
    if card:
        content = f'<a href="{esc(card[3])}" style="color:{fg};font-weight:600">#{esc(card[1])} {esc(card[2])}</a>'
        if card[4]:
            content += f": {linkify(card[4])}"
    else:
        content = linkify(b["text"])
    return (
        f'<tr><td style="padding:0 0 12px"><div style="background:{bg};border-radius:10px;'
        f'padding:12px 16px;color:{fg};font-size:15px;line-height:22px">'
        f'<span style="margin-right:8px">{b["icon"]}</span>{content}</div></td></tr>'
    )


def card_html(it):
    fg, _ = TONE[it["icon"]]
    note_color = C["muted"] if it["icon"] == "✅" else fg
    note = (
        f'<div style="margin-top:4px;font-size:14px;line-height:21px;color:{note_color}">{linkify(it["note"])}</div>'
        if it["note"] else ""
    )
    return (
        '<tr><td style="padding:12px 0;border-top:1px solid #EEF0F3">'
        '<table role="presentation" cellpadding="0" cellspacing="0" width="100%"><tr>'
        f'<td valign="top" width="28" style="font-size:16px;line-height:22px">{it["icon"]}</td>'
        f'<td valign="top"><a href="{esc(it["url"])}" style="color:{C["ink"]};font-weight:600;font-size:15px;'
        f'line-height:22px;text-decoration:none"><span style="color:{C["muted"]};font-weight:500">'
        f'#{esc(it["num"])}</span>&nbsp; {esc(it["title"])}</a>{note}</td></tr></table></td></tr>'
    )


def section_html(b):
    return (
        '<tr><td style="padding:8px 0 16px">'
        f'<table role="presentation" cellpadding="0" cellspacing="0" width="100%" style="background:{C["card"]};'
        f'border-radius:16px;border:1px solid {C["ring"]}">'
        '<tr><td style="padding:16px 20px 4px">'
        f'<span style="font-size:13px;font-weight:700;letter-spacing:0.06em;text-transform:uppercase;'
        f'color:{C["ink"]}">{esc(b["title"])}</span>'
        f'<span style="display:inline-block;margin-left:8px;background:{C["accent"]};color:{C["ink"]};'
        f'border-radius:999px;padding:1px 9px;font-size:12px;font-weight:700">{esc(b["count"])}</span>'
        '</td></tr><tr><td style="padding:4px 20px 8px">'
        '<table role="presentation" cellpadding="0" cellspacing="0" width="100%">'
        + "".join(card_html(it) for it in b["items"])
        + "</table></td></tr></table></td></tr>"
    )


def report_to_html(subject, text, now=None):
    now = now or datetime.now()
    headline = re.sub(r"^Triage cards:\s*", "", subject)
    when = now.strftime("%A, %B %-d at %-I:%M %p")
    rows = []
    for b in parse_report(text):
        if b["type"] == "section":
            rows.append(section_html(b))
        elif b["type"] == "status":
            rows.append(status_html(b))
        else:
            rows.append(
                f'<tr><td style="padding:0 0 12px;font-size:15px;line-height:22px;color:{C["ink"]}">'
                f'{linkify(b["text"])}</td></tr>'
            )
    return f"""<!doctype html>
<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>{esc(subject)}</title></head>
<body style="margin:0;padding:0;background:{C["page"]}">
<table role="presentation" cellpadding="0" cellspacing="0" width="100%" style="background:{C["page"]};font-family:{FONT}">
  <tr><td align="center" style="padding:24px 16px">
    <table role="presentation" cellpadding="0" cellspacing="0" width="100%" style="max-width:600px">
      <tr><td style="background:{C["header"]};border-radius:16px;padding:20px 24px">
        <div style="font-size:12px;font-weight:700;letter-spacing:0.08em;text-transform:uppercase;color:{C["accent"]}">Triage report</div>
        <div style="margin-top:6px;font-size:22px;line-height:28px;font-weight:700;color:#FFFFFF">{esc(headline)}</div>
        <div style="margin-top:4px;font-size:13px;color:#D1D5DB">{esc(when)}</div>
      </td></tr>
      <tr><td style="height:16px"></td></tr>
      {"".join(rows)}
    </table>
  </td></tr>
</table>
</body></html>"""
