#!/usr/bin/env python3
# 由 docs/report_source.md 生成设计报告 docx。
# 用法: python script/build-report.py
# 依赖: python-docx（pip install python-docx）
import os
import re
import sys

from docx import Document
from docx.enum.table import WD_TABLE_ALIGNMENT
from docx.enum.text import WD_ALIGN_PARAGRAPH, WD_LINE_SPACING
from docx.oxml.ns import qn
from docx.shared import Cm, Pt, RGBColor

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "docs", "report_source.md")
OUT = os.path.join(ROOT, "docs", "Harvest_Finance_攻击复现_设计报告.docx")

doc = Document()
sec = doc.sections[0]
sec.top_margin = Cm(2.54)
sec.bottom_margin = Cm(2.54)
sec.left_margin = Cm(3.0)
sec.right_margin = Cm(3.0)

normal = doc.styles["Normal"]
normal.font.name = "Times New Roman"
normal.font.size = Pt(12)
normal.element.rPr.rFonts.set(qn("w:eastAsia"), "宋体")
normal.paragraph_format.line_spacing_rule = WD_LINE_SPACING.ONE_POINT_FIVE
normal.paragraph_format.space_after = Pt(3)


def font(run, cn="宋体", en="Times New Roman", size=12, bold=False, color=None):
    run.font.name = en
    run.font.size = Pt(size)
    run.font.bold = bold
    run._element.rPr.rFonts.set(qn("w:eastAsia"), cn)
    if color:
        run.font.color.rgb = color


def heading(text, level):
    p = doc.add_paragraph(style="Heading 1" if level == 1 else "Heading 2")
    p.paragraph_format.space_before = Pt(12 if level == 1 else 8)
    p.paragraph_format.space_after = Pt(6)
    p.paragraph_format.keep_with_next = True
    font(p.add_run(text), "黑体", "Times New Roman", 16 if level == 1 else 13.5, True, RGBColor(0, 0, 0))


def body(text):
    p = doc.add_paragraph()
    p.paragraph_format.first_line_indent = Pt(24)
    for part in re.split(r"(\*\*[^*]+\*\*)", text):
        if not part:
            continue
        if part.startswith("**") and part.endswith("**"):
            font(p.add_run(part[2:-2]), bold=True)
        else:
            font(p.add_run(part))


def table(rows):
    header, rest = rows[0], rows[1:]
    t = doc.add_table(rows=1, cols=len(header))
    t.style = "Table Grid"
    t.alignment = WD_TABLE_ALIGNMENT.CENTER
    for i, h in enumerate(header):
        cell = t.rows[0].cells[i]
        cell.text = ""
        p = cell.paragraphs[0]
        p.alignment = WD_ALIGN_PARAGRAPH.CENTER
        font(p.add_run(h.strip()), "黑体", "Times New Roman", 10.5, True)
    for row in rest:
        cells = t.add_row().cells
        for i, val in enumerate(row[: len(header)]):
            cells[i].text = ""
            font(cells[i].paragraphs[0].add_run(val.strip()), "宋体", "Times New Roman", 10.5)
    doc.add_paragraph().paragraph_format.space_after = Pt(2)


def picture(alt, path):
    full = os.path.join(ROOT, path)
    if not os.path.exists(full):
        p = doc.add_paragraph()
        p.alignment = WD_ALIGN_PARAGRAPH.CENTER
        font(p.add_run("[缺少图片: " + path + " —— 运行 script/screenshot-pages.ps1 后再重新生成本文档]"), size=10)
        return
    doc.add_picture(full, width=Cm(14.4))
    doc.paragraphs[-1].alignment = WD_ALIGN_PARAGRAPH.CENTER
    cap = doc.add_paragraph()
    cap.alignment = WD_ALIGN_PARAGRAPH.CENTER
    r = cap.add_run(alt)
    font(r, size=10)
    r.font.italic = True


lines = open(SRC, encoding="utf-8-sig").read().split("\n")
i = 0
buf = []
while i < len(lines):
    line = lines[i].rstrip()
    if line.startswith("|"):
        buf.append([c for c in line.strip().strip("|").split("|")])
        i += 1
        continue
    if buf:
        if len(buf) > 1:
            table([r for r in buf if not re.match(r"^\s*:?-{2,}", r[0])])
        buf = []
    if line.startswith("# "):
        p = doc.add_paragraph()
        p.alignment = WD_ALIGN_PARAGRAPH.CENTER
        p.paragraph_format.space_after = Pt(10)
        font(p.add_run(line[2:]), "黑体", "Times New Roman", 20, True)
    elif line.startswith("## "):
        heading(line[3:], 1)
    elif line.startswith("### "):
        heading(line[4:], 2)
    elif line.startswith("!["):
        m = re.match(r"!\[(.*?)\]\((.*?)\)", line)
        if m:
            picture(m.group(1), m.group(2))
    elif re.match(r"^\d+\.\s", line):
        p = doc.add_paragraph(re.sub(r"^\d+\.\s", "", line), style="List Number")
        for r in p.runs:
            font(r)
    elif line.startswith("- "):
        p = doc.add_paragraph(line[2:], style="List Bullet")
        for r in p.runs:
            font(r)
    elif line.strip() == "":
        pass
    else:
        body(line)
    i += 1
if buf and len(buf) > 1:
    table([r for r in buf if not re.match(r"^\s*:?-{2,}", r[0])])

doc.save(OUT)
text = open(SRC, encoding="utf-8-sig").read()
print("saved:", OUT)
print("chinese chars:", len(re.findall(r"[\u4e00-\u9fff]", text)))
