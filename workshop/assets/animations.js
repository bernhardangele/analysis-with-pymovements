// GSAP animations for the workshop slides. Each animation starts when its slide is shown.
(function () {
  const STEPS = ["1 read", "2 trial times", "3 regions", "4 fixations → regions", "5 reading window",
                 "6 cleaning", "7 reading measures", "8 statistics (R)"];

  // analysis pipeline: stages appear one after the other
  function pipeline(slide) {
    slide.querySelectorAll(".pipeline").forEach(p => {
      const tl = gsap.timeline();
      p.querySelectorAll(".stage, .arrow").forEach(el =>
        tl.fromTo(el, {opacity: 0, y: el.classList.contains("arrow") ? 0 : 25, x: el.classList.contains("arrow") ? -15 : 0},
                  {opacity: 1, y: 0, x: 0, duration: 0.35, ease: "power2.out"}, "-=0.1"));
    });
  }

  // step strip at the bottom of the frases-comas slides: where are we in the analysis?
  function buildStrips() {
    document.querySelectorAll(".step-strip").forEach(s => {
      const step = +s.dataset.step;
      s.innerHTML = STEPS.map((name, i) =>
        `<span class="${i + 1 < step ? "done" : i + 1 === step ? "current" : ""}">${name}</span>`).join("");
    });
  }
  function strip(slide) {
    const current = slide.querySelector(".step-strip .current");
    if (!current) return;
    gsap.fromTo(slide.querySelectorAll(".step-strip .done"), {backgroundColor: "#edf2f7"},
                {backgroundColor: "#c3dafe", duration: 0.3, stagger: 0.06});
    gsap.fromTo(current, {scale: 0.6, opacity: 0}, {scale: 1, opacity: 1, duration: 0.6, ease: "back.out(2)", delay: 0.2});
  }

  // animated scanpath: the reader's fixations in real time, with the reading measures adding up
  const SVG = "http://www.w3.org/2000/svg";
  function el(name, attrs, parent) {
    const e = document.createElementNS(SVG, name);
    for (const [k, v] of Object.entries(attrs)) e.setAttribute(k, v);
    parent && parent.appendChild(e);
    return e;
  }
  function buildScanpath(box) {
    const d = JSON.parse(box.dataset.trial);
    const x0 = Math.min(...d.regions.map(r => r.x_start)) - 20, x1 = Math.max(...d.regions.map(r => r.x_end)) + 20;
    const svg = el("svg", {viewBox: `${x0} 0 ${x1 - x0} 150`});
    box.prepend(svg);
    const rects = {};
    for (const r of d.regions) {
      rects[r.region] = el("rect", {x: r.x_start, y: 25, width: r.x_end - r.x_start, height: 70, rx: 4,
                                    fill: r.critical ? "#fbd38d" : "#e2e8f0", opacity: 0.45}, svg);
      el("text", {x: r.x_start + 4, y: 20, "font-size": 16, fill: "#4a5568"}, svg).textContent = r.label.split(" ")[0];
    }
    for (const c of d.chars)
      el("text", {x: c.x + 8, y: 66, "text-anchor": "middle", "font-family": "monospace", "font-size": 22}, svg)
        .textContent = c.c;
    const trail = el("g", {}, svg);
    const eye = el("circle", {cx: d.fixations[0].x, cy: 58, r: 0, fill: "#2b6cb0", opacity: 0.55}, svg);
    const info = el("text", {x: x0 + 10, y: 130, "font-size": 22, fill: "#2b3e50"}, svg);

    // table of measures, filled in while the animation runs
    const measures = ["first fixation", "gaze duration", "go-past time", "total time"];
    const table = document.createElement("table");
    table.innerHTML = `<tr><th></th>${d.regions.map(r => `<th>${r.label}</th>`).join("")}</tr>` +
      measures.map((m, i) => `<tr><th>${m}</th>${d.regions.map(r => `<td data-m="${i}" data-r="${r.region}"></td>`).join("")}</tr>`).join("");
    box.appendChild(table);
    const cell = (m, r) => table.querySelector(`td[data-m="${m}"][data-r="${r}"]`);

    function timeline() {
      trail.innerHTML = "";
      table.querySelectorAll("td").forEach(td => (td.textContent = ""));
      const sums = {ffd: {}, gd: {}, gp: {}, tvt: {}}, gpOpen = {};
      const tl = gsap.timeline({paused: true});
      d.fixations.forEach((f, i) => {
        tl.to(eye, {attr: {cx: f.x, r: 6}, duration: 0.04, ease: "none"});           // saccade
        tl.add(() => {
          info.textContent = `fixation ${i + 1}: ${f.duration} ms on ${f.label}` +
            (f.region == null ? "" : f.first_pass ? " (first pass)" : " (rereading)");
          if (f.region != null) gsap.fromTo(rects[f.region], {opacity: 0.9}, {opacity: 0.45, duration: 0.6});
        });
        tl.to(eye, {attr: {r: 4 + Math.sqrt(f.duration)}, duration: f.duration / 1000, ease: "none"});  // fixation
        tl.add(() => {
          el("circle", {cx: f.x, cy: 58 + (i % 2 ? 6 : -6), r: 3 + Math.sqrt(f.duration) / 2,
                        fill: f.first_pass ? "#2b6cb0" : "#dd6b20", opacity: 0.35}, trail);
          if (f.region == null) return;
          const r = f.region;
          sums.tvt[r] = (sums.tvt[r] || 0) + f.duration;
          cell(3, r).textContent = sums.tvt[r];
          // go-past: from entering a region in first pass until a region further right is fixated
          for (const g of Object.keys(gpOpen)) {
            if (!gpOpen[g]) continue;
            if (r > g) { gpOpen[g] = false; continue; }
            cell(2, g).textContent = (sums.gp[g] += f.duration);
          }
          if (f.first_pass && !(r in gpOpen)) { gpOpen[r] = true; cell(2, r).textContent = (sums.gp[r] = f.duration); }
          if (f.first_pass) {
            if (!(r in sums.ffd)) cell(0, r).textContent = (sums.ffd[r] = f.duration);
            sums.gd[r] = (sums.gd[r] || 0) + f.duration;
            cell(1, r).textContent = sums.gd[r];
          }
        });
      });
      tl.to(eye, {attr: {r: 0}, duration: 0.2});
      return tl;
    }
    let tl = timeline();
    box.querySelector(".replay").onclick = () => { tl.kill(); tl = timeline(); tl.timeScale(1).play(); };
    box.querySelector(".slow").onclick = () => { tl.kill(); tl = timeline(); tl.timeScale(0.4).play(); };
    box.play = () => { tl.kill(); tl = timeline(); tl.play(); };
  }

  function onSlide(slide) {
    if (!slide || typeof gsap === "undefined") return;
    pipeline(slide);
    strip(slide);
    slide.querySelectorAll(".scanpath-anim").forEach(b => b.play && b.play());
  }

  function init() {
    buildStrips();
    document.querySelectorAll(".scanpath-anim").forEach(buildScanpath);
    Reveal.on("slidechanged", e => onSlide(e.currentSlide));
    onSlide(Reveal.getCurrentSlide());
  }
  window.addEventListener("load", () => {
    if (!window.Reveal) return;
    Reveal.isReady() ? init() : Reveal.on("ready", init);
  });
})();
