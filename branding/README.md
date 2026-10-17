# Branding sources

`logo.webp` (square, logo on black) and `wallpaper.webp` (16:9) are the
originals. Everything the image ships (menu icons, launcher tile, boot splash,
the watermark-free wallpaper and four generated variants in the same palette)
is produced from them by:

```sh
python3 -m venv .venv && .venv/bin/pip install pillow
.venv/bin/python scripts/make-assets.py branding/src stage-custom/10-branding/files
```

Replace the two source files and rerun to rebrand.
