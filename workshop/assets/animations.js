// GSAP animations for the workshop slides. Each animation starts when its slide is shown.
// The data of .scanpath-anim / .samples-anim / .aoi-anim come from a hidden Python chunk (data-trial JSON).
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
      // a deck can set its own step names: data-steps="a|b|c" on the strip, or window.STEP_NAMES
      const steps = s.dataset.steps ? s.dataset.steps.split("|") : (window.STEP_NAMES || STEPS);
      s.innerHTML = steps.map((name, i) =>
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
    const columns = d.regions.filter(r => r.table !== false);   // a deck can show only some regions in the table
    table.innerHTML = `<tr><th></th>${columns.map(r => `<th>${r.label}</th>`).join("")}</tr>` +
      measures.map((m, i) => `<tr><th>${m}</th>${columns.map(r => `<td data-m="${i}" data-r="${r.region}"></td>`).join("")}</tr>`).join("");
    box.appendChild(table);
    const put = (m, r, value) => {
      const td = table.querySelector(`td[data-m="${m}"][data-r="${r}"]`);
      if (td) td.textContent = value;
      return value;
    };

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
          put(3, r, sums.tvt[r]);
          // go-past: from entering a region in first pass until a region further right is fixated
          for (const g of Object.keys(gpOpen)) {
            if (!gpOpen[g]) continue;
            if (r > g) { gpOpen[g] = false; continue; }
            put(2, g, (sums.gp[g] += f.duration));
          }
          if (f.first_pass && !(r in gpOpen)) { gpOpen[r] = true; put(2, r, (sums.gp[r] = f.duration)); }
          if (f.first_pass) {
            if (!(r in sums.ffd)) put(0, r, (sums.ffd[r] = f.duration));
            sums.gd[r] = (sums.gd[r] || 0) + f.duration;
            put(1, r, sums.gd[r]);
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

  // replay / slow-motion buttons and the automatic start on the slide, shared by the animations below
  function controls(box, timeline) {
    let tl = null;
    const run = (speed, ...args) => { tl && tl.kill(); tl = timeline(...args); tl.timeScale(speed).play(); };
    const replay = box.querySelector(".replay"), slow = box.querySelector(".slow");
    if (replay) replay.onclick = () => run(1);
    if (slow) slow.onclick = () => run(0.35);
    box.play = () => run(1);
    return run;
  }

  // samples -> velocity -> saccades and fixations: a playhead moves through the first second of a trial
  const COLOURS = {fixation: "#2b6cb0", saccade: "#e53e3e", blink: "#a0aec0"};
  let clipCount = 0;
  function buildSamples(box) {
    const d = JSON.parse(box.dataset.trial), T = d.x.length;
    const L = 60, R = 1185, A = [34, 180], B = [224, 330], E = [366, 384];
    const svg = el("svg", {viewBox: "0 0 1200 450"});
    box.prepend(svg);
    const sx = t => L + (R - L) * t / T;
    const xs = d.x.filter(v => v != null), xmin = Math.min(...xs), xmax = Math.max(...xs);
    const vmax = Math.max(...d.v.filter(v => v != null));
    const ya = x => A[1] - 6 - (x - xmin) / (xmax - xmin) * (A[1] - A[0] - 12);
    const yb = v => B[1] - v / vmax * (B[1] - B[0] - 4);
    const path = (values, y) => values.map((v, t) =>
      v == null ? "" : `${t === 0 || values[t - 1] == null ? "M" : "L"}${sx(t).toFixed(1)} ${y(v).toFixed(1)}`).join("");
    const title = (y, text) => (el("text", {x: L, y, "font-size": 17, fill: "#2b3e50", "font-weight": "bold"}, svg).textContent = text);
    const small = (x, y, text, attrs) =>
      (el("text", Object.assign({x, y, "font-size": 14, fill: "#4a5568"}, attrs || {}), svg).textContent = text);

    // frames, axes
    title(A[0] - 12, "Samples: horizontal gaze position, one sample per millisecond");
    title(B[0] - 12, "Velocity: how fast does the position change?");
    title(E[0] - 10, "The EyeLink's own events (SFIX/EFIX, SSACC/ESACC, SBLINK/EBLINK)");
    for (const [top, bottom] of [A, B])
      el("rect", {x: L, y: top, width: R - L, height: bottom - top, fill: "#f7fafc", stroke: "#cbd5e0"}, svg);
    small(L - 6, ya(xmin) + 5, Math.round(xmin) + " px", {"text-anchor": "end"});
    small(L - 6, ya(xmax) + 5, Math.round(xmax) + " px", {"text-anchor": "end"});
    small(L - 6, yb(0) + 2, "0", {"text-anchor": "end"});
    small(L - 6, yb(vmax) + 10, Math.round(vmax) + "°/s", {"text-anchor": "end"});
    for (let t = 0; t <= T; t += 200) {
      el("line", {x1: sx(t), x2: sx(t), y1: E[1] + 4, y2: E[1] + 9, stroke: "#718096"}, svg);
      small(sx(t), E[1] + 24, t === 0 ? "0 ms (STIMONSET)" : t, {"text-anchor": t === 0 ? "start" : "middle"});
    }

    // what the threshold finds: bands (saccade, blink) and bars (fixation), hidden until the playhead arrives
    const found = d.detected.map(s => {
      const g = el("g", {opacity: 0}, svg), x = sx(s.t0), w = Math.max(sx(s.t1) - x, 3);
      if (s.type === "fixation") {
        el("rect", {x, y: A[0] + 3, width: w, height: 7, rx: 3, fill: COLOURS.fixation}, g);
        el("text", {x: x + w / 2, y: A[0] + 26, "font-size": 14, "text-anchor": "middle", fill: COLOURS.fixation}, g)
          .textContent = w > 60 ? `fixation ${s.t1 - s.t0} ms` : "";
      } else {
        for (const [top, bottom] of [A, B])
          el("rect", {x, y: top, width: w, height: bottom - top, fill: COLOURS[s.type], opacity: 0.25}, g);
        if (s.type === "blink")
          el("text", {x: x + w / 2, y: A[1] - 10, "font-size": 14, "text-anchor": "middle", fill: "#4a5568"}, g)
            .textContent = "blink: no data";
      }
      return g;
    });

    // traces, revealed from left to right
    const id = "samples-clip-" + clipCount++;
    const clip = el("rect", {x: L, y: 0, width: 0, height: 450}, el("clipPath", {id}, el("defs", {}, svg)));
    const traces = el("g", {"clip-path": `url(#${id})`}, svg);
    el("path", {d: path(d.x, ya), fill: "none", stroke: "#2b3e50", "stroke-width": 2}, traces);
    el("path", {d: path(d.v, yb), fill: "none", stroke: "#2b3e50", "stroke-width": 1.5}, traces);
    el("line", {x1: L, x2: R, y1: yb(d.threshold), y2: yb(d.threshold), stroke: COLOURS.saccade,
                "stroke-dasharray": "6 4", "stroke-width": 1.5}, svg);
    small(R - 4, yb(d.threshold) - 5, `threshold: ${d.threshold}°/s`, {"text-anchor": "end", fill: COLOURS.saccade});
    const head = el("line", {x1: L, x2: L, y1: A[0], y2: B[1], stroke: "#dd6b20", "stroke-width": 2}, svg);

    // the tracker's events, shown at the end for comparison
    const eyelink = d.eyelink.map(s => el("rect", {x: sx(s.t0), y: E[0], width: Math.max(sx(s.t1) - sx(s.t0), 3),
                                                   height: E[1] - E[0], rx: 3, fill: COLOURS[s.type], opacity: 0}, svg));
    const info = el("text", {x: L, y: 438, "font-size": 18, fill: "#2b3e50"}, svg);
    const say = text => () => (info.textContent = text);

    controls(box, () => {
      const SECONDS = 7, at = t => SECONDS * t / T;
      gsap.set(found.concat(eyelink), {opacity: 0});
      const tl = gsap.timeline({paused: true});
      tl.add(say("The eye rests (flat line), then jumps: position changes fast, velocity has a peak."), 0);
      tl.fromTo(clip, {attr: {width: 0}}, {attr: {width: R - L}, duration: SECONDS, ease: "none"}, 0);
      tl.fromTo(head, {attr: {x1: L, x2: L}, opacity: 1}, {attr: {x1: R, x2: R}, duration: SECONDS, ease: "none"}, 0);
      d.detected.forEach((s, i) => {
        tl.to(found[i], {opacity: 1, duration: 0.25}, at(s.type === "fixation" ? s.t1 : s.t0));
        if (s.type === "saccade" && i < 4)
          tl.add(say(`Velocity above ${d.threshold}°/s → saccade (${s.t1 - s.t0} ms). ` +
                     "What lies between two saccades is a fixation."), at(s.t0));
        if (s.type === "blink")
          tl.add(say("Eye closed: no samples. The fixations next to a blink are not trustworthy."), at(s.t0));
      });
      tl.to(head, {opacity: 0, duration: 0.3}, SECONDS);
      tl.add(say("The EyeLink did the same while recording (velocity and acceleration thresholds): " +
                 "we use its fixations."), SECONDS);
      tl.to(eyelink, {opacity: 0.85, duration: 0.3, stagger: 0.08}, SECONDS + 0.2);
      return tl;
    });
  }

  // interest areas: REGION messages become boxes, then every fixation gets the word whose box it is in
  function buildAoi(box) {
    const d = JSON.parse(box.dataset.trial);
    const x0 = Math.min(...d.regions.map(r => r.left)) - 20, x1 = Math.max(...d.regions.map(r => r.right)) + 20;
    const top = Math.min(...d.regions.map(r => r.top)), bottom = Math.max(...d.regions.map(r => r.bottom));
    const svg = el("svg", {viewBox: `${x0} ${top - 40} ${x1 - x0} ${bottom - top + 125}`});
    box.prepend(svg);
    const EMPTY = "#ebf4ff", HIT = "#fbd38d", rects = {};
    const boxes = d.regions.map(r => {
      const g = el("g", {}, svg);
      rects[r.n] = el("rect", {x: r.left, y: r.top, width: r.right - r.left, height: r.bottom - r.top,
                               fill: EMPTY, stroke: "#2b6cb0", "stroke-width": 1.5}, g);
      el("text", {x: (r.left + r.right) / 2, y: r.top - 8, "font-size": 17, "text-anchor": "middle", fill: "#2b6cb0"}, g)
        .textContent = r.n;
      return g;
    });
    for (const r of d.regions)     // the sentence: 14.4 px per letter, half a space on each side of the word
      el("text", {x: r.left + 7.2, y: (r.top + r.bottom) / 2 + 8, "font-family": "monospace", "font-size": 24,
                  textLength: 14.4 * r.label.length, lengthAdjust: "spacingAndGlyphs"}, svg).textContent = r.label;
    const trail = el("g", {}, svg);
    const eye = el("circle", {cx: x0, cy: (top + bottom) / 2, r: 0, fill: "#2b6cb0", opacity: 0.6}, svg);
    const info = el("text", {x: x0 + 20, y: bottom + 62, "font-size": 21, fill: "#2b3e50"}, svg);

    const run = controls(box, (index = 0, intro = true) => {
      const trial = d.trials[index];
      trail.innerHTML = "";
      gsap.set(Object.values(rects), {attr: {fill: EMPTY}});
      gsap.set(eye, {attr: {r: 0}});
      const tl = gsap.timeline({paused: true});
      if (intro) {
        tl.set(boxes, {opacity: 0});
        d.regions.forEach((r, i) => {
          tl.add(() => {
            info.setAttribute("font-family", "monospace");
            info.textContent = `MSG … REGION n=${r.n} label=${r.label} left=${r.left} top=${r.top} ` +
                               `right=${r.right} bottom=${r.bottom}`;
          });
          tl.fromTo(boxes[i], {opacity: 0}, {opacity: 1, duration: 0.3});
        });
        tl.to({}, {duration: 0.5});
      } else tl.set(boxes, {opacity: 1});
      trial.fixations.forEach((f, i) => {
        tl.to(eye, {attr: {cx: f.x, cy: f.y, r: 9}, duration: 0.12, ease: "power1.inOut"});
        tl.add(() => {
          info.setAttribute("font-family", "sans-serif");
          info.textContent = `${trial.name}, fixation ${i + 1} at x = ${f.x}, y = ${f.y}: ` +
            (f.n == null ? "outside every interest area → no word" : `inside box ${f.n} → word “${f.label}”`);
          if (f.n != null) gsap.fromTo(rects[f.n], {attr: {fill: "#ed8936"}}, {attr: {fill: HIT}, duration: 0.5});
          el("circle", {cx: f.x, cy: f.y, r: 3 + Math.sqrt(f.duration) / 2, opacity: 0.45,
                        fill: f.n == null ? COLOURS.saccade : COLOURS.fixation}, trail);
          el("text", {x: f.x, y: f.y + 30, "font-size": 15, "text-anchor": "middle", fill: "#4a5568"}, trail)
            .textContent = i + 1;
        });
        tl.to(eye, {attr: {r: 5 + Math.sqrt(f.duration) / 1.5}, duration: f.duration / 400, ease: "none"});
      });
      tl.to(eye, {attr: {r: 0}, duration: 0.2});
      tl.add(() => {
        const inside = trial.fixations.filter(f => f.n != null).length;
        info.textContent = `${trial.name}: ${inside} of ${trial.fixations.length} fixations are on a word; ` +
                           "words without a fixation were skipped.";
      });
      return tl;
    });
    box.querySelectorAll("button.trial").forEach(b => (b.onclick = () => run(1, +b.dataset.trialIndex, false)));
  }

  function onSlide(slide) {
    if (!slide || typeof gsap === "undefined") return;
    pipeline(slide);
    strip(slide);
    slide.querySelectorAll(".scanpath-anim, .samples-anim, .aoi-anim").forEach(b => b.play && b.play());
  }

  function init() {
    buildStrips();
    document.querySelectorAll(".scanpath-anim").forEach(buildScanpath);
    document.querySelectorAll(".samples-anim").forEach(buildSamples);
    document.querySelectorAll(".aoi-anim").forEach(buildAoi);
    Reveal.on("slidechanged", e => onSlide(e.currentSlide));
    onSlide(Reveal.getCurrentSlide());
  }
  window.addEventListener("load", () => {
    if (!window.Reveal) return;
    Reveal.isReady() ? init() : Reveal.on("ready", init);
  });
})();
