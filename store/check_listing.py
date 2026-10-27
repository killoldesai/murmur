#!/usr/bin/env python3
"""Checks the App Store field limits in store/listing.md."""
import re, sys, pathlib

text = pathlib.Path(__file__).with_name("listing.md").read_text()
failed = False

def field(label):
    m = re.search(r"\| " + re.escape(label) + r" \| `([^`]*)` \| (\d+) \|", text)
    return m.group(1), int(m.group(2))

for label in ["App name", "Subtitle", "Promotional text", "Keywords"]:
    value, limit = field(label)
    ok = len(value) <= limit
    failed |= not ok
    print(f"{'ok ' if ok else 'BAD'} {label}: {len(value)}/{limit}")

description = re.search(r"## Description\n\n```\n(.*?)\n```", text, re.S).group(1)
ok = len(description) <= 4000
failed |= not ok
print(f"{'ok ' if ok else 'BAD'} Description: {len(description)}/4000")
sys.exit(1 if failed else 0)
