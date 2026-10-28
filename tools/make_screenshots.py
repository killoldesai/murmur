#!/usr/bin/env python3
"""Builds App Store screenshots from the CI simulator screenshots.

Flat colours only (no gradients, glows or blur). Each image is the real app screen plus
a caption, the Murmur logo badge, a flat waveform strip and one or two small chips.

Usage: python3 tools/make_screenshots.py <dir with the ci-results PNGs> <output dir>
Sizes: iPhone 6.9" 1320x2868, iPad 13" 2064x2752, Mac 2880x1800, Watch 416x496.
"""
import os
import sys
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
ICON = os.path.join(HERE, "..", "store", "icon-1024.png")
WAVES = [(0xFF, 0x5A, 0x6E)] * 3  # one colour (record coral) on every image and device
ACCENT, TEXT, SUB = (0x5E, 0xE0, 0xC6), (0xF4, 0xF3, 0xF8), (0xB9, 0xB7, 0xC8)
# (background, frame border, waveform/chip surface): all solid brand tones
THEMES = [
    ((0x11, 0x11, 0x16), (0x2A, 0x2A, 0x33), (0x1C, 0x1C, 0x23)),
    ((0x12, 0x2B, 0x27), (0x24, 0x4A, 0x43), (0x1A, 0x3D, 0x37)),
    ((0x1C, 0x1C, 0x23), (0x33, 0x33, 0x3E), (0x11, 0x11, 0x16)),
]
FONT_BOLD = "/usr/share/fonts/opentype/inter/Inter-Bold.otf"
FONT_REG = "/usr/share/fonts/opentype/inter/Inter-Regular.otf"
FONT_SEMI = "/usr/share/fonts/opentype/inter/Inter-SemiBold.otf"


def font(path, size):
    return ImageFont.truetype(path if os.path.exists(path) else FONT_BOLD, size)


def rounded(img, radius):
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, img.size[0], img.size[1]), radius, fill=255)
    out = img.convert("RGBA")
    out.putalpha(mask)
    return out


def logo_badge(draw, canvas, cx, y, size, label_colour):
    """Icon + wordmark, centred on cx."""
    icon = Image.open(ICON).convert("RGBA").resize((size, size), Image.LANCZOS)
    icon = rounded(icon, int(size * 0.225))
    f = font(FONT_BOLD, int(size * 0.62))
    text = "Murmur"
    gap = int(size * 0.3)
    total = size + gap + draw.textlength(text, font=f)
    x = int(cx - total / 2)
    canvas.paste(icon, (x, y), icon)
    draw.text((x + size + gap, y + size * 0.5), text, font=f, fill=label_colour, anchor="lm")


def waveform(draw, x0, x1, y_mid, max_h, bar_w, gap, colour):
    """Flat rounded bars shaped like a voice: a swelling envelope, tallest in the middle."""
    import math
    n = int((x1 - x0 + gap) // (bar_w + gap))
    for i in range(n):
        t = i / max(1, n - 1)
        envelope = 0.25 + 0.75 * math.sin(math.pi * t) ** 1.5
        ripple = 0.55 + 0.45 * abs(math.sin(i * 1.7) * math.cos(i * 0.45))
        h = max(bar_w, int(max_h * envelope * ripple))
        x = x0 + i * (bar_w + gap)
        draw.rounded_rectangle((x, y_mid - h // 2, x + bar_w, y_mid + h // 2), bar_w // 2, fill=colour)


def chips(draw, cx, y, labels, size, surface, border):
    f = font(FONT_SEMI, size)
    pad_x, pad_y, gap = int(size * 0.9), int(size * 0.5), int(size * 0.6)
    widths = [draw.textlength(t, font=f) + 2 * pad_x for t in labels]
    x = cx - (sum(widths) + gap * (len(labels) - 1)) / 2
    h = size + 2 * pad_y
    for t, w in zip(labels, widths):
        draw.rounded_rectangle((x, y, x + w, y + h), h // 2, fill=surface, outline=border, width=max(2, size // 14))
        draw.text((x + w / 2, y + h / 2), t, font=f, fill=ACCENT, anchor="mm")
        x += w + gap
    return y + h


def headline(draw, canvas_w, y, lines, size, accent_word):
    f = font(FONT_BOLD, size)
    for line in lines:
        w = draw.textlength(line, font=f)
        x = (canvas_w - w) / 2
        if accent_word and accent_word in line:
            before, after = line.split(accent_word, 1)
            for part, colour in ((before, TEXT), (accent_word, ACCENT), (after, TEXT)):
                draw.text((x, y), part, font=f, fill=colour)
                x += draw.textlength(part, font=f)
        else:
            draw.text((x, y), line, font=f, fill=TEXT)
        y += int(size * 1.16)
    return y


def compose(out_path, size, shot_path, entry, theme, wave_colour, shot_width, top, hl, radius, border, wave=True):
    lines, sub, accent, tags = entry
    bg, line, surface = theme
    W, H = size
    canvas = Image.new("RGB", size, bg)
    draw = ImageDraw.Draw(canvas)
    badge = int(hl * 0.62)
    logo_badge(draw, canvas, W // 2, int(H * 0.035), badge, TEXT)
    y = headline(draw, W, int(H * 0.035) + badge + int(hl * 0.55), lines, hl, accent)
    sf = font(FONT_REG, int(hl * 0.40))
    sw = draw.textlength(sub, font=sf)
    draw.text(((W - sw) / 2, y + hl * 0.08), sub, font=sf, fill=SUB)
    y_chip = int(y + hl * 0.08 + hl * 0.40 * 1.7)
    y_end = chips(draw, W // 2, y_chip, tags, int(hl * 0.30), surface, line)
    if wave:
        waveform(draw, 0, W, y_end + int(hl * 0.55), int(hl * 0.85), max(10, hl // 12), max(8, hl // 16), wave_colour)

    shot = Image.open(shot_path).convert("RGB")
    shot = shot.resize((shot_width, int(shot.size[1] * shot_width / shot.size[0])), Image.LANCZOS)
    fw, fh = shot_width + 2 * border, shot.size[1] + 2 * border
    frame = rounded(Image.new("RGBA", (fw, fh), line + (255,)), radius + border)
    frame.alpha_composite(rounded(shot, radius), (border, border))
    canvas.paste(frame, ((W - fw) // 2, max(top, y_end + int(hl * 0.95))), frame)
    canvas.save(out_path, "PNG")


T = ["Private · Offline", "No account"]
IPHONE = [
    ("recording", ["Transcribe on", "your iPhone"], "Private and offline. Nothing leaves your device.", "iPhone", ["On-device", "Free to try"]),
    ("note", ["Every word,", "every speaker"], "Tap any line to hear it again.", "speaker", ["Speaker labels", "Tap to play"]),
    ("summary", ["Summaries and", "action items"], "Meeting, lecture or bullet points.", "action items", ["Apple Intelligence", "Private"]),
    ("library", ["All your notes,", "in one place"], "Folders, search and Apple Watch recordings.", "one place", ["Folders", "Watch"]),
    ("search", ["Find any", "word, fast"], "Search every transcript and summary.", "word", ["Instant", "Offline"]),
    ("dictionary", ["Teach it", "your words"], "Names and jargon, spelled right.", "your words", ["Custom words", "Better accuracy"]),
    ("find-replace", ["Fix a name", "everywhere"], "Find and replace across a whole note.", "everywhere", ["Find & replace", "One tap"]),
]
IPAD = [
    ("ipad-recording", ["Record with", "total privacy"], "On-device transcription. No account, no cloud.", "privacy", T),
    ("ipad-note-wide", ["Transcript beside", "the summary"], "See action items and who spoke how much.", "summary", ["Summary", "Talk time"]),
    ("ipad-library", ["Your notes,", "at a glance"], "Folders, search and quick playback.", "at a glance", ["Folders", "Search"]),
    ("ipad-search", ["Search with", "context"], "See each match in its conversation.", "context", ["Instant", "Offline"]),
    ("ipad-import", ["Drop audio in,", "get text out"], "Import from Files, Photos or Voice Memos.", "text out", ["Drag & drop", "Video too"]),
    ("ipad-settings", ["Yours to", "control"], "Language, models and storage on your terms.", "control", ["Your data", "Your iPad"]),
    ("ipad-paywall", ["Go Pro,", "keep it private"], "3-day free trial. Cancel anytime.", "Pro", ["Yearly", "Lifetime"]),
]
MAC = [
    ("mac-main", ["Fast, private", "transcription"], "Runs on Apple silicon. Your audio never leaves your Mac.", "private", T),
    ("mac-queue", ["Drop files in,", "get text out"], "Batch-transcribe audio and video in the background.", "text out", ["Batch", "Background"]),
    ("mac-export", ["Export", "any way"], "Text, subtitles, audio or Markdown.", "any way", ["TXT", "SRT"]),
    ("mac-recording", ["Record from", "the menu bar"], "A global shortcut starts recording anywhere.", "menu bar", ["⌃⌥R", "Floating"]),
    ("mac-settings", ["Make it", "yours"], "Pick your model, language and shortcut.", "yours", ["Models", "Dictionary"]),
    ("mac-paywall", ["Go Pro,", "keep it private"], "3-day free trial. Cancel anytime.", "Pro", ["Yearly", "Lifetime"]),
]
WATCH = ["watch-home", "watch-recording", "watch-saved", "watch-recent", "watch-playback", "watch-complications"]


def run(out, sub, items, size, src, **kw):
    os.makedirs(os.path.join(out, sub), exist_ok=True)
    n = 0
    for name, *entry in items:
        shot = os.path.join(src, f"{name}.png")
        if not os.path.exists(shot):
            print("missing", shot)
            continue
        n += 1
        compose(os.path.join(out, sub, f"{n}-{name}.png"), size, shot, tuple(entry), THEMES[(n - 1) % 3], WAVES[(n - 1) % 3], **kw)


def watch_set(out, src):
    """Watch shots stay as the real screen on a flat panel (416x496), with no extras."""
    os.makedirs(os.path.join(out, "watch"), exist_ok=True)
    n = 0
    for name in WATCH:
        shot = os.path.join(src, f"{name}.png")
        if not os.path.exists(shot):
            print("missing", shot)
            continue
        n += 1
        img = Image.open(shot).convert("RGB")
        scale = min(416 / img.size[0], 496 / img.size[1])
        img = img.resize((int(img.size[0] * scale), int(img.size[1] * scale)), Image.LANCZOS)
        canvas = Image.new("RGB", (416, 496), (0x11, 0x11, 0x16))
        canvas.paste(img, ((416 - img.size[0]) // 2, (496 - img.size[1]) // 2))
        canvas.save(os.path.join(out, "watch", f"{n}-{name}.png"), "PNG")


def main():
    src, out = sys.argv[1], sys.argv[2]
    run(out, "iphone-6.9", IPHONE, (1320, 2868), src, shot_width=1040, top=900, hl=112, radius=96, border=10)
    run(out, "ipad-13", IPAD, (2064, 2752), src, shot_width=1560, top=900, hl=140, radius=64, border=10)
    run(out, "mac", MAC, (2880, 1800), src, shot_width=1900, top=560, hl=92, radius=24, border=6)
    watch_set(out, src)


if __name__ == "__main__":
    main()
