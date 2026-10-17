#!/usr/bin/python3
"""Patch a labwc rc.xml: rounded corners, drop shadows, Inter titlebar font.

    labwc-rc-patch.py SRC DEST
"""
import sys
import xml.etree.ElementTree as ET

src, dest = sys.argv[1], sys.argv[2]
tree = ET.parse(src)
root = tree.getroot()
theme = root.find("theme")
if theme is None:
    theme = ET.SubElement(root, "theme")


def set_text(parent, tag, text):
    node = parent.find(tag)
    if node is None:
        node = ET.SubElement(parent, tag)
    node.text = text


set_text(theme, "cornerRadius", "10")
set_text(theme, "dropShadows", "yes")
for node in list(theme.findall("font")):
    if node.get("place") in (None, "ActiveWindow", "InactiveWindow", "MenuItem"):
        theme.remove(node)
for place in ("ActiveWindow", "InactiveWindow"):
    ET.SubElement(theme, "font", place=place, name="Inter", size="10", weight="Medium")
ET.SubElement(theme, "font", place="MenuItem", name="Inter", size="10")
tree.write(dest, encoding="UTF-8", xml_declaration=True)
