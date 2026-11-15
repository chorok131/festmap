#!/usr/bin/env python3
"""sitemap.xml의 lastmod를 각 페이지(와 행사 데이터)의 마지막 git 커밋 날짜로 갱신."""
import re, subprocess, pathlib
root = pathlib.Path(__file__).resolve().parent.parent
sm = root / "sitemap.xml"
def last(*paths):
    ds = [subprocess.run(["git","log","-1","--format=%cs","--",p],cwd=root,capture_output=True,text=True).stdout.strip() for p in paths]
    ds = [d for d in ds if d]
    return max(ds) if ds else None
def repl(m):
    loc = m.group(1)
    path = loc.split("minimap.kr/",1)[1]
    ev = re.search(r"event=([\w-]+)", path)
    if ev: d = last("e.html", f"events/{ev.group(1)}")
    else: d = last(path.split("?")[0] or "index.html")
    return m.group(0) if not d else re.sub(r"<lastmod>.*?</lastmod>", f"<lastmod>{d}</lastmod>", m.group(0))
txt = sm.read_text()
new = re.sub(r"<loc>(.*?)</loc>\s*<lastmod>.*?</lastmod>", repl, txt, flags=re.S)
sm.write_text(new); print("updated" if new!=txt else "no change")
