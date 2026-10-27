#!/usr/bin/env python3
"""Renders the Murmur app icons from the "Waveform M" design (docs/design/Final.dc.html).

Usage:  python3 tools/make_icons.py        (needs playwright + Pillow)
Writes the three asset catalogs under App/ and a 1024 px store icon in store/.
Flat colours only: no gradients, no glow.
"""
import io, json, pathlib
from PIL import Image
from playwright.sync_api import sync_playwright

ROOT = pathlib.Path(__file__).resolve().parent.parent
BG, TEAL, TEAL_LIGHT = "#15151B", "#5EE0C6", "#7FF2DA"

FIVE = [(26, 27, 73), (38, 35, 62), (50, 45, 55), (62, 35, 62), (74, 27, 73)]   # x, y1, y2
THREE = [(28, 28, 72), (50, 44, 58), (72, 28, 72)]


def bars(items, color, width):
    lines = "".join(f'<line x1="{x}" y1="{a}" x2="{x}" y2="{b}"/>' for x, a, b in items)
    return f'<g stroke="{color}" stroke-width="{width}" stroke-linecap="round">{lines}</g>'


def square_svg(bg, color, items=FIVE, width=7.5):
    """Full-bleed square for iOS and watchOS (the system applies the mask)."""
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100" width="100%" height="100%">'
            f'<rect width="100" height="100" fill="{bg}"/>{bars(items, color, width)}</svg>')


MAC_FIVE = [(30.8, 30.6, 67.4), (40.4, 37, 58.6), (50, 45, 53), (59.6, 37, 58.6), (69.2, 30.6, 67.4)]
MAC_THREE = [(33, 31, 67), (50, 44, 54), (67, 31, 67)]


def mac_svg(small):
    items, width = (MAC_THREE, 9) if small else (MAC_FIVE, 6)
    return ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100" width="100%" height="100%">'
            '<defs><filter id="s" x="-20%" y="-20%" width="140%" height="140%">'
            '<feDropShadow dx="0" dy="2.5" stdDeviation="2.5" flood-color="#000" flood-opacity="0.28"/></filter></defs>'
            f'<rect x="10" y="9" width="80" height="80" rx="18" fill="{BG}" filter="url(#s)"/>'
            '<rect x="10.5" y="9.5" width="79" height="79" rx="17.5" fill="none" stroke="#fff" stroke-opacity="0.12"/>'
            f'{bars(items, TEAL, width)}</svg>')


def write_json(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2) + "\n")


def main():
    with sync_playwright() as p:
        browser = p.chromium.launch()

        def render(svg, size, transparent):
            page = browser.new_page(viewport={"width": size, "height": size}, device_scale_factor=1)
            page.set_content(f'<html><body style="margin:0;background:{"transparent" if transparent else "#000"}">'
                             f'<div style="width:{size}px;height:{size}px">{svg}</div></body></html>')
            png = page.screenshot(omit_background=transparent, clip={"x": 0, "y": 0, "width": size, "height": size})
            page.close()
            img = Image.open(io.BytesIO(png))
            return img.convert("RGBA") if transparent else img.convert("RGB")

        # iOS: default, dark, tinted. 1024, opaque.
        ios = ROOT / "App/Murmur/Assets.xcassets"
        write_json(ios / "Contents.json", {"info": {"author": "xcode", "version": 1}})
        icon = ios / "AppIcon.appiconset"
        icon.mkdir(parents=True, exist_ok=True)
        variants = {
            "icon-default.png": square_svg(BG, TEAL),
            "icon-dark.png": square_svg("#000000", TEAL_LIGHT),
            "icon-tinted.png": square_svg("#000000", "#FFFFFF"),
        }
        for name, svg in variants.items():
            render(svg, 1024, False).save(icon / name)
        write_json(icon / "Contents.json", {
            "images": [
                {"filename": "icon-default.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"},
                {"appearances": [{"appearance": "luminosity", "value": "dark"}], "filename": "icon-dark.png",
                 "idiom": "universal", "platform": "ios", "size": "1024x1024"},
                {"appearances": [{"appearance": "luminosity", "value": "tinted"}], "filename": "icon-tinted.png",
                 "idiom": "universal", "platform": "ios", "size": "1024x1024"},
            ],
            "info": {"author": "xcode", "version": 1},
        })
        store = ROOT / "store"
        store.mkdir(parents=True, exist_ok=True)
        render(variants["icon-default.png"], 1024, False).save(store / "icon-1024.png")

        # watchOS: one 1024 square, the system masks it to a circle.
        watch = ROOT / "App/MurmurWatch/Assets.xcassets"
        write_json(watch / "Contents.json", {"info": {"author": "xcode", "version": 1}})
        wicon = watch / "AppIcon.appiconset"
        wicon.mkdir(parents=True, exist_ok=True)
        watch_items = [(28, 32, 68), (39, 38, 60), (50, 46, 54), (61, 38, 60), (72, 32, 68)]
        render(square_svg(BG, TEAL, watch_items, 7.5), 1024, False).save(wicon / "icon-watch.png")
        write_json(wicon / "Contents.json", {
            "images": [{"filename": "icon-watch.png", "idiom": "universal", "platform": "watchos", "size": "1024x1024"}],
            "info": {"author": "xcode", "version": 1},
        })

        # macOS: 16, 32, 128, 256, 512 at 1x and 2x. Transparent corners and shadow come from the design.
        mac = ROOT / "App/MurmurMac/Assets.xcassets"
        write_json(mac / "Contents.json", {"info": {"author": "xcode", "version": 1}})
        micon = mac / "AppIcon.appiconset"
        micon.mkdir(parents=True, exist_ok=True)
        images = []
        for point in (16, 32, 128, 256, 512):
            for scale in (1, 2):
                px = point * scale
                name = f"icon_{point}x{point}@{scale}x.png"
                render(mac_svg(small=px <= 32), px, True).save(micon / name)
                images.append({"filename": name, "idiom": "mac", "scale": f"{scale}x", "size": f"{point}x{point}"})
        write_json(micon / "Contents.json", {"images": images, "info": {"author": "xcode", "version": 1}})
        browser.close()


if __name__ == "__main__":
    main()
