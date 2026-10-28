"""Check a rendered revealjs presentation: does the content of every slide fit, and how large are the figures?

    python tools/check_slides.py workshop/presentation.html [--screenshots DIR]

For each slide (with all fragments shown) it reports
  - elements that stick out of the slide (text cut off at the bottom or right),
  - code blocks and output that need a scroll bar,
  - images whose displayed size is less than a third of the slide area.
Exits with 1 if any slide has overflowing content. Needs `pip install playwright` and
`playwright install --with-deps chromium`.
"""

import argparse
import sys
from pathlib import Path

from playwright.sync_api import sync_playwright

CHECK = """() => {
  const slide = Reveal.getCurrentSlide();
  const area = document.querySelector('.reveal .slides').getBoundingClientRect();
  const scale = Reveal.getScale();
  const title = (slide.querySelector('h1, h2') || {}).textContent || '(no title)';
  const visible = el => { const s = getComputedStyle(el); return s.display !== 'none' && s.visibility !== 'hidden'; };
  const out = [], scroll = [], small = [];
  for (const el of slide.querySelectorAll('*')) {
    if (!visible(el) || el.closest('.slide-menu-button, .footer, aside.notes')) continue;
    const r = el.getBoundingClientRect();
    if (r.width === 0 || r.height === 0) continue;
    const bottom = r.bottom - area.bottom, right = r.right - area.right;
    if ((bottom > 2 || right > 2) && el.children.length === 0)
      out.push(`${el.tagName.toLowerCase()} "${el.textContent.trim().slice(0, 40)}" +${Math.round(Math.max(bottom, right) / scale)}px`);
    if (['PRE', 'DIV', 'CODE'].includes(el.tagName) && (el.scrollHeight > el.clientHeight + 2 || el.scrollWidth > el.clientWidth + 2)
        && ['auto', 'scroll'].some(v => getComputedStyle(el).overflowY === v || getComputedStyle(el).overflowX === v))
      scroll.push(`${el.className || el.tagName.toLowerCase()} ${el.scrollWidth}x${el.scrollHeight} in ${el.clientWidth}x${el.clientHeight}`);
  }
  for (const img of slide.querySelectorAll('img, svg:not(.reveal svg svg)')) {
    const r = img.getBoundingClientRect();
    const share = (r.width * r.height) / (area.width * area.height);
    if (r.width > 0 && share < 1 / 3)
      small.push(`${img.tagName.toLowerCase()} ${Math.round(r.width / scale)}x${Math.round(r.height / scale)}px (${Math.round(100 * share)}% of slide)`);
  }
  return {title: title.trim(), out, scroll, small};
}"""


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("html", type=Path)
    parser.add_argument("--screenshots", type=Path)
    args = parser.parse_args()
    if args.screenshots:
        args.screenshots.mkdir(parents=True, exist_ok=True)

    problems = 0
    with sync_playwright() as p:
        browser = p.chromium.launch()
        page = browser.new_page(viewport={"width": 1600, "height": 900})
        page.goto(args.html.resolve().as_uri())
        page.wait_for_function("window.Reveal && Reveal.isReady()")
        indices = page.evaluate("Reveal.getSlides().map(s => Reveal.getIndices(s))")
        for n, ix in enumerate(indices, 1):
            page.evaluate(f"Reveal.slide({ix['h']}, {ix.get('v') or 0}, 999)")   # 999: show all fragments
            page.wait_for_timeout(500)   # slide transition
            # jump to the end of the GSAP animations, so that everything they show is measured
            page.evaluate("window.gsap && gsap.globalTimeline.getChildren(true, true, false).forEach(t => t.progress(1))")
            page.wait_for_timeout(200)
            res = page.evaluate(CHECK)
            if args.screenshots:
                page.screenshot(path=args.screenshots / f"{n:02d}.png")
            flags = []
            if res["out"]:
                problems += 1
                flags.append("OVERFLOW " + "; ".join(res["out"][:3]))
            if res["scroll"]:
                flags.append("SCROLL " + "; ".join(res["scroll"][:2]))
            if res["small"]:
                flags.append("SMALL " + "; ".join(res["small"][:2]))
            print(f"{n:2d} {res['title'][:60]:60s} {'ok' if not flags else ''}")
            for f in flags:
                print("     " + f)
        browser.close()
    print(f"\n{problems} slide(s) with overflowing content")
    sys.exit(1 if problems else 0)


if __name__ == "__main__":
    main()
