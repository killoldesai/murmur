#!/usr/bin/env python3
"""Builds App Store screenshots from the CI simulator screenshots (flat colours, no gradients).

Usage: python3 tools/make_screenshots.py <dir with the ci-results PNGs> <output dir>
Sizes: iPhone 6.9" 1320x2868, iPad 13" 2064x2752, Mac 2880x1800.
"""
import os
import sys
from PIL import Image, ImageDraw, ImageFont

BG, BORDER, ACCENT, TEXT, SUB = (0x11, 0x11, 0x16), (0x2A, 0x2A, 0x33), (0x5E, 0xE0, 0xC6), (0xF4, 0xF3, 0xF8), (0xB9, 0xB7, 0xC8)
FONT_BOLD = "/usr/share/fonts/opentype/inter/Inter-Bold.otf"
FONT_REG = "/usr/share/fonts/opentype/inter/Inter-Regular.otf"


def rounded(img, radius):
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, img.size[0], img.size[1]), radius, fill=255)
    out = img.convert("RGBA")
    out.putalpha(mask)
    return out


def draw_headline(draw, canvas_w, y, lines, size, accent_word=None):
    font = ImageFont.truetype(FONT_BOLD, size)
    for line in lines:
        w = draw.textlength(line, font=font)
        x = (canvas_w - w) / 2
        if accent_word and accent_word in line:
            before, after = line.split(accent_word, 1)
            for part, colour in ((before, TEXT), (accent_word, ACCENT), (after, TEXT)):
                draw.text((x, y), part, font=font, fill=colour)
                x += draw.textlength(part, font=font)
        else:
            draw.text((x, y), line, font=font, fill=TEXT)
        y += int(size * 1.18)
    return y


def compose(out_path, size, shot_path, lines, sub, accent_word, shot_width, top, headline_size, radius, border):
    canvas = Image.new("RGB", size, BG)
    draw = ImageDraw.Draw(canvas)
    y = draw_headline(draw, size[0], int(size[1] * 0.045), lines, headline_size, accent_word)
    sub_font = ImageFont.truetype(FONT_REG, int(headline_size * 0.42))
    w = draw.textlength(sub, font=sub_font)
    draw.text(((size[0] - w) / 2, y + headline_size * 0.12), sub, font=sub_font, fill=SUB)

    shot = Image.open(shot_path).convert("RGB")
    scale = shot_width / shot.size[0]
    shot = shot.resize((shot_width, int(shot.size[1] * scale)), Image.LANCZOS)
    framed_w, framed_h = shot_width + 2 * border, shot.size[1] + 2 * border
    frame = Image.new("RGBA", (framed_w, framed_h), BORDER + (255,))
    frame = rounded(frame, radius + border)
    frame.alpha_composite(rounded(shot, radius), (border, border))
    canvas.paste(frame, ((size[0] - framed_w) // 2, top), frame)
    canvas.save(out_path, "PNG")


IPHONE = [
    ("recording", ["Transcribe on", "your iPhone"], "Private and offline. Nothing leaves your device.", "iPhone"),
    ("note", ["Every word,", "every speaker"], "Tap any line to hear it again.", "speaker"),
    ("summary", ["Summaries and", "action items"], "Meeting, lecture or bullet points.", "action items"),
    ("library", ["All your notes,", "in one place"], "Folders, search and Apple Watch recordings.", "one place"),
    ("dictionary", ["Teach it", "your words"], "Names and jargon, spelled right.", "your words"),
]
IPAD = [
    ("ipad-recording", ["Record with", "total privacy"], "On-device transcription. No account, no cloud.", "privacy"),
    ("ipad-note-wide", ["Transcript beside", "the summary"], "See action items and who spoke how much.", "summary"),
    ("ipad-library", ["Your notes,", "at a glance"], "Folders, search and quick playback.", "at a glance"),
]
MAC = [
    ("mac-main", ["Fast, private", "transcription"], "Runs on Apple silicon. Your audio never leaves your Mac.", "private"),
    ("mac-queue", ["Drop files in,", "get text out"], "Batch-transcribe audio and video in the background.", "text out"),
]


def main():
    src, out = sys.argv[1], sys.argv[2]
    for sub in ("iphone-6.9", "ipad-13", "mac"):
        os.makedirs(os.path.join(out, sub), exist_ok=True)
    for i, (name, lines, sub, accent) in enumerate(IPHONE, 1):
        compose(os.path.join(out, "iphone-6.9", f"{i}-{name}.png"), (1320, 2868), os.path.join(src, f"{name}.png"),
                lines, sub, accent, shot_width=1040, top=620, headline_size=118, radius=96, border=10)
    for i, (name, lines, sub, accent) in enumerate(IPAD, 1):
        compose(os.path.join(out, "ipad-13", f"{i}-{name}.png"), (2064, 2752), os.path.join(src, f"{name}.png"),
                lines, sub, accent, shot_width=1700, top=640, headline_size=150, radius=64, border=10)
    for i, (name, lines, sub, accent) in enumerate(MAC, 1):
        compose(os.path.join(out, "mac", f"{i}-{name}.png"), (2880, 1800), os.path.join(src, f"{name}.png"),
                lines, sub, accent, shot_width=1700, top=430, headline_size=96, radius=24, border=6)


if __name__ == "__main__":
    main()
