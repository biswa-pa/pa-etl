"""Bake the PA ETL branding into Prefect's own UI files at image build time.

Prefect serves two UIs (V1 at /, V2 at /v2) from static folders inside its Python package.
This copies the brand files next to them (served at /__pa/...), patches both index.html files
to load the theme and brand script, and swaps the icons. The result is a Prefect image that
looks like PA ETL with no proxy in front, so it can replace the official prefecthq/prefect image.
"""
import os
import re
import shutil
import sys

import prefect

BRAND = "/tmp/pa-brand"
FILES = ["logo.svg", "logo-dark.svg", "mark.svg", "mark-animated.svg", "icon.png",
         "apple-icon.png", "favicon.ico", "prefect.css", "brand.js"]
TAGS = '<link rel="stylesheet" href="/__pa/prefect.css"><script defer src="/__pa/brand.js"></script>'


def patch(ui_dir: str) -> None:
    if not os.path.isdir(ui_dir):
        print(f"skip (missing): {ui_dir}")
        return
    # 1. brand files, served at /__pa/ (the V1 bundle is mounted at the site root)
    target = os.path.join(ui_dir, "__pa")
    os.makedirs(target, exist_ok=True)
    for name in FILES:
        shutil.copy(os.path.join(BRAND, name), os.path.join(target, name))

    # 2. index.html: title and theme/script tags
    index = os.path.join(ui_dir, "index.html")
    html = open(index, encoding="utf-8").read()
    html = re.sub(r"<title>[^<]*</title>", "<title>PA ETL &middot; Pipelines</title>", html, count=1)
    if "/__pa/prefect.css" not in html:
        html = html.replace("</head>", TAGS + "</head>", 1)
    open(index, "w", encoding="utf-8").write(html)

    # 3. icons: every favicon / touch icon file gets the PA ETL mark
    icon = open(os.path.join(BRAND, "icon.png"), "rb").read()
    apple = open(os.path.join(BRAND, "apple-icon.png"), "rb").read()
    swapped = 0
    for root, _, files in os.walk(ui_dir):
        if "__pa" in root.split(os.sep):
            continue
        for f in files:
            low = f.lower()
            if not (low.startswith("favicon") or low.startswith("apple-touch-icon") or low.startswith("android-chrome")):
                continue
            data = apple if low.startswith("apple") else icon
            open(os.path.join(root, f), "wb").write(data)
            swapped += 1
    # The pages ask for /favicon.ico and /favicon-dark.ico at the root; make sure they exist.
    for name in ("favicon.ico", "favicon-dark.ico"):
        path = os.path.join(ui_dir, name)
        if not os.path.exists(path):
            open(path, "wb").write(icon)
            swapped += 1
    print(f"patched {ui_dir}: brand files, index.html, {swapped} icon files")


for attr in ("__ui_static_path__", "__ui_v2_static_path__"):
    patch(str(getattr(prefect, attr)))
