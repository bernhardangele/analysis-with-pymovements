"""Analysis of the frases-comas experiment (Angele, Gutierrez-Cordero, Perea & Marcet) with pymovements.

The experiment was run with the UMass EyeTrack software on an EyeLink 1000+ (right eye, 1000 Hz). The original
pipeline was

    ASC --Tim10drop.pl--> .da1 (fixations on characters) --EyeDry--> .IXS (measures per region) --R--> paper

This module replaces the Perl and C steps with Python working on data read by pymovements:

* ``load_recording``      pymovements reads the ASC file (samples, EyeLink events, messages)
* ``doctor_recording``    port of Tim10drop.pl: fixations -> characters, merging of short fixations,
                          flagging of trials with blinks / long fixations near the critical region
* ``eyedry_measures``     port of the EyeDry routines for first fixation, first pass (gaze), go-past and total time

Both ports reproduce the original files: the .da1 text is identical, and the measures equal EyeDry's output.
``eyedry_read_fixations(..., overrun=True)`` also reproduces a bug in EyeDry that added fixations from
earlier trials (see the slides).
"""

from __future__ import annotations

import re
from pathlib import Path

import numpy as np
import polars as pl
import pymovements as pm

DATA_DIR = Path(__file__).resolve().parents[2] / "workshop" / "data" / "frases-comas"
EDF_DIR = DATA_DIR / "edf"

# parameters used for the paper (see edf/commas2.sum, edf/commas.ctl)
CRITICAL_REGION = 2  # pre-comma region
MERGE_PIXELS = 16  # combine a fixation < MERGE_MS with a neighbour at most this many pixels away
MERGE_MS = 80
LONG_FIXATION = 800  # trials with a longer fixation on/next to the critical region are flagged (98)
SHORT_TIME = 80  # EyeDry ignores fixations <= 80 ms
LONG_TIME = 4000  # ... and > 4000 ms
GD_CUTOFF = 2000  # EyeDry "upper summed cutoff for first pass time"
TVT_CUTOFF = 4000  # EyeDry "upper summed cutoff for total time"
SCREEN_WIDTH_CHARS = 160


# --------------------------------------------------------------------------------------------------------------------
# Reading data with pymovements
# --------------------------------------------------------------------------------------------------------------------

def patch_eyelink_event_parsing() -> None:
    """Let pymovements 0.28 parse EFIX/ESACC lines with negative or missing ('.') coordinates.

    The regular expressions in pymovements only accept unsigned numbers, so a fixation with an average x of -4.1 px
    (gaze slightly left of the screen) is silently dropped. 52 such fixations occur during sentence display here.
    """
    from pymovements.gaze._utils import _parsing_eyelink as pe

    num = r"(-?\d+[.]?\d*|[.])"
    pe.FIXATION_STOP_REGEX = (
        r"EFIX\s+(?P<eye>R|L)\s+(?P<timestamp_start>(\d+[.]?\d*))\s+"
        r"(?P<timestamp_end>(\d+[.]?\d*))\s+(?P<duration_ms>(\d+[.]?\d*))\s+"
        rf"(?P<avg_x_pix>{num})\s+(?P<avg_y_pix>{num})\s+(?P<avg_pupil>{num})\s*.*"
    )
    pe.SACCADE_STOP_REGEX = (
        r"ESACC\s+(?P<eye>R|L)\s+(?P<timestamp_start>(\d+[.]?\d*))\s+"
        r"(?P<timestamp_end>(\d+[.]?\d*))\s+(?P<duration_ms>(\d+[.]?\d*))\s+"
        rf"(?P<start_x_pix>{num})\s+(?P<start_y_pix>{num})\s+"
        rf"(?P<end_x_pix>{num})\s+(?P<end_y_pix>{num})\s+"
        rf"(?P<amplitude>{num})\s+(?P<peak_velocity>{num})\s*.*"
    )


def load_recording(path: str | Path) -> pm.Gaze:
    """Read an ASC file with samples, EyeLink events and messages; add the mean position of each fixation."""
    gaze = pm.gaze.from_asc(path, events=True, messages=True)
    gaze.messages = gaze.messages.with_columns(pl.col("time").cast(pl.Int64))
    events = gaze.events.frame
    gaze.events = pm.Events(events.filter(pl.col("name") == "fixation_eyelink"))
    gaze.compute_event_properties(("location", {"position_column": "pixel", "method": "mean"}))
    # keep blinks next to the fixations (compute_event_properties needs a single event type)
    gaze.events = pm.Events(pl.concat([
        gaze.events.frame,
        events.filter(pl.col("name") == "blink_eyelink").with_columns(pl.lit(None, pl.List(pl.Float64)).alias("location")),
    ]).sort("onset"))
    return gaze


def fixations_from_gaze(gaze: pm.Gaze) -> pl.DataFrame:
    """EyeLink fixations with their mean x/y position, rounded to 0.1 px like the EFIX line."""
    return (
        gaze.events.frame.filter(pl.col("name") == "fixation_eyelink")
        .select(
            "onset", "offset",
            pl.col("location").list.get(0).round(1).alias("x"),
            pl.col("location").list.get(1).round(1).alias("y"),
        )
        .sort("offset")
    )


def blinks_from_gaze(gaze: pm.Gaze) -> pl.DataFrame:
    return gaze.events.frame.filter(pl.col("name") == "blink_eyelink").select("onset", "offset").sort("onset")


TRIALID = r"^TRIALID (?P<type>[A-Z])(?P<cond>\d+)I(?P<item>\d+)D(?P<dep>\d+)"
REGION_CHAR = r"^REGION CHAR (?P<char_idx>\d+) (?P<line>\d+) (?P<char>.) (?P<x1>\d+) (?P<y1>\d+) (?P<x2>\d+) (?P<y2>\d+)$"


def trials_from_messages(messages: pl.DataFrame) -> pl.DataFrame:
    """One row per trial attempt: type (E = experimental, F = question, P = practice), condition, item, timing."""
    m = messages.with_columns(trial=pl.col("content").str.starts_with("TRIALID").cum_sum()).filter(pl.col("trial") > 0)

    def first(prefix, name, col="time"):
        return (m.filter(pl.col("content").str.starts_with(prefix))
                 .group_by("trial").agg(pl.col(col).first().alias(name)))

    return (
        m.filter(pl.col("content").str.starts_with("TRIALID"))
        .select("trial", pl.col("time").alias("trialid"), pl.col("content").str.extract_groups(TRIALID).alias("g"))
        .unnest("g")
        .with_columns(pl.col("cond", "item", "dep").cast(pl.Int64))
        .join(first("DISPLAY ON", "display_on"), on="trial", how="left")
        .join(first("ENDBUTTON", "end_button"), on="trial", how="left")
        .join(first("TRIAL OK", "trial_ok"), on="trial", how="left")
        .join(m.filter(pl.col("content").str.starts_with("ENDBUTTON"))
               .group_by("trial").agg(pl.col("content").first().str.extract(r"(\d+)").cast(pl.Int64).alias("button")),
              on="trial", how="left")
        .join(m.filter(pl.col("content").str.starts_with("QUESTION_ANSWER"))
               .group_by("trial").agg(pl.col("content").first().str.extract(r"(\d+)").cast(pl.Int64).alias("correct_button")),
              on="trial", how="left")
        .sort("trial")
    )


def characters_from_messages(messages: pl.DataFrame) -> pl.DataFrame:
    """Character boxes (pixels) that EyeTrack writes as REGION CHAR messages after DISPLAY TEXT."""
    m = messages.with_columns(trial=pl.col("content").str.starts_with("TRIALID").cum_sum())
    return (
        m.filter(pl.col("content").str.starts_with("REGION CHAR"))
        .select("trial", pl.col("content").str.extract_groups(REGION_CHAR).alias("g"))
        .unnest("g")
        .with_columns(pl.col("char_idx", "line", "x1", "y1", "x2", "y2").cast(pl.Int64))
    )


def read_regions(path: str | Path = EDF_DIR / "frases_c.cnt") -> pl.DataFrame:
    """EyeDry count file: item, condition, number of regions, then region starts (characters) and the end."""
    rows = []
    for line in open(path):
        p = line.split()
        if not p:
            continue
        item, cond, n = int(p[0]), int(p[1]), int(p[2])
        b = [int(v) for v in p[3:4 + n]]
        rows += [(item, cond, r, b[r - 1], b[r]) for r in range(1, n + 1)]
    return pl.DataFrame(rows, schema=["item", "cond", "region", "char_start", "char_end"], orient="row")


# --------------------------------------------------------------------------------------------------------------------
# Tim10drop.pl
# --------------------------------------------------------------------------------------------------------------------

class _PerlList(list):
    """List with Perl array semantics: negative indices count from the end, missing/empty elements read as 0."""

    def at(self, i):
        if i < 0:
            i += len(self)
        if 0 <= i < len(self):
            v = self[i]
            return 0 if v == "" else v
        return 0


def _event_stream(gaze: pm.Gaze):
    """Messages, blink starts and fixation ends in the order Tim10drop reads them from the ASC file."""
    # at equal time stamps, EFIX lines (written when the fixation ends) usually follow the messages
    stream = [(t, 0, "MSG", c) for t, c in gaze.messages.select("time", "content").iter_rows()]
    stream += [(t, 0, "SBLINK", None) for t in blinks_from_gaze(gaze)["onset"]]
    stream += [(off, 1, "EFIX", (on, off, x)) for on, off, x, _ in fixations_from_gaze(gaze).iter_rows()]
    stream.sort(key=lambda e: (e[0], e[1]))
    return stream




def doctor_recording(gaze: pm.Gaze, regions: pl.DataFrame, crit_region: int = CRITICAL_REGION,
                     pix_comb: int = MERGE_PIXELS, ms_comb: int = MERGE_MS, longcut: int = LONG_FIXATION):
    """Python port of Tim10drop.pl with the settings used for the paper.

    Returns ``(trials, fixations, da1_lines)``: counts per experimental trial, one row per fixation (``char`` =
    character index, ``line`` = -1 when the fixation is off the text) and the text of the .da1 file.
    Condition 99 marks trials with a blink and 98 trials with a fixation > 800 ms on or next to the critical region.

    The port is deliberately literal, including two quirks of the Perl script (a fixation on the last character
    keeps the character of the previous fixation; after a merge, later blink flags in that trial shift by one),
    so that it reproduces the original .da1 files.
    """
    crit = {(r["item"], r["cond"]): (r["char_start"], r["char_end"])
            for r in regions.filter(pl.col("region") == crit_region).iter_rows(named=True)}
    trials, fixations, da1 = [], [], []
    trialnum, displayon, blink, fix_xchar, getcharpix = 0, 0, 0, 0, 2
    st = {}
    for time, _, kind, payload in _event_stream(gaze):
        if kind == "MSG":
            if payload.startswith("TRIALID"):
                g = re.match(TRIALID, payload)
                item, cond = int(g["item"]), int(g["cond"])
                st = dict(type=g["type"], item=item, cond=cond, orig_cond=cond, done=0, trialok=0,
                          crit=crit.get((item, cond), (-2, -2)), pixx=[""])
                displayon = 0
            elif payload.startswith("DISPLAY TEXT"):
                getcharpix = 1 if payload.split()[2] == "1" else 2
            elif payload.startswith("REGION") and getcharpix == 1:
                st["pixx"].append(int(re.match(REGION_CHAR, payload)["x1"]))
            elif payload.startswith("TRIAL OK"):
                st["trialok"] = 1
            elif payload.startswith("DISPLAY ON"):
                st.update(t0=time, initC=_PerlList([""]), initP=_PerlList([""]), blinker=_PerlList([""]),
                          fixcount=0, shortcount=0, longcount=0, num_comb=0)
                displayon, getcharpix = 1, 2
            elif payload.startswith("ENDBUTTON"):
                st["done"] = 2
        elif kind == "SBLINK":
            blink = 1
        elif kind == "EFIX" and displayon == 1:
            onset, offset, x = payload
            fixstart = max(onset, st["t0"])
            if st["fixcount"] == 0 and fixstart > st["t0"]:
                st["t0"] = fixstart  # trial time starts with the first fixation if DISPLAY ON fell into a saccade
            t0 = st["t0"]
            xpos = round(x) if x is not None else -10 ** 6  # sprintf("%.0f") rounds half to even, like round()
            pixx = st["pixx"]
            fix_ychar = 0
            if len(pixx) > 1:
                if xpos < pixx[1] or xpos > pixx[-1] + 11:
                    fix_xchar, fix_ychar = -1, -1
                else:
                    for c in range(1, len(pixx) - 1):  # the last character is never matched (quirk)
                        if pixx[c] <= xpos < pixx[c + 1]:
                            fix_xchar = c - 1
                            break
            st["fixcount"] += 1
            st["initC"] += [fix_xchar, fix_ychar, fixstart - t0, offset - t0]
            st["initP"] += [xpos, 540, fixstart - t0, offset - t0]
            st["blinker"].append(blink)
            blink = 0
        if st.get("type") == "E" and st.get("done") == 2:
            st["done"] = 1
            _tim10drop_trial(st, pix_comb, ms_comb, longcut)
        if st.get("trialok") == 1 and st.get("done", 0) >= 1:
            if st["type"] == "E":
                blinker, fin = st["blinker"], st["finC"]
                numblink = sum(blinker.at(i) for i in range(len(blinker) - 1))
                cond = f" {st['cond']}" if st["cond"] == st["orig_cond"] else str(st["cond"])
                da1.append(f"{trialnum}\t {cond}\t {st['item']}\t {numblink}  \t {st['shortcount']}\t "
                           f"{st['num_comb']}\t {st['fixcount']}\t {st['fixcount'] - st['num_comb']}\t"
                           + "".join(f"{v}\t" for v in fin[1:]) + "\n")
                trials.append(dict(seq=trialnum, item=st["item"], cond_orig=st["orig_cond"], cond=st["cond"],
                                   nfix=st["fixcount"], nshort=st["shortcount"], nlong=st["longcount"],
                                   ncomb=st["num_comb"], nblink=numblink))
                for k in range(1, len(fin) - 3, 4):
                    fixations.append(dict(seq=trialnum, item=st["item"], cond=st["cond"], fix=(k + 3) // 4,
                                          char=fin[k], line=fin[k + 1], start=fin[k + 2], end=fin[k + 3]))
            displayon = 0
            trialnum += 1
            st["trialok"] = st["done"] = 0
    return pl.DataFrame(trials), pl.DataFrame(fixations), da1


def _tim10drop_trial(st, pix_comb, ms_comb, longcut):
    """Merge short fixations and flag the trial (Tim10drop, first-pass-or-later blink check, 1 critical region)."""
    P, C, blinker = st["initP"], st["initC"], st["blinker"]
    finP, finC = _PerlList([""]), _PerlList([""])

    def keep(i, end=None, start=None, src=None):
        s = i if src is None else src
        finP.extend([P.at(s), P.at(s + 1), P.at(i + 2) if start is None else start, P.at(s + 3) if end is None else end])
        finC.extend([C.at(s), C.at(s + 1), C.at(i + 2) if start is None else start, C.at(s + 3) if end is None else end])

    i = 1
    while i < len(P) - 1:
        cur = (i + 3) // 4
        dur = P.at(i + 3) - P.at(i + 2)
        if dur > longcut:
            st["longcount"] += 1
        if dur < ms_comb and blinker.at(cur) == 0:
            st["shortcount"] += 1
            prenear = abs(P.at(i) - P.at(i - 4))
            postnear = abs(P.at(i) - P.at(i + 4))
            if prenear <= postnear and prenear <= pix_comb:
                if blinker.at(cur - 1) == 0:  # merge with the previous fixation (else: drop it)
                    finP.pop(); finP.append(P.at(i + 3))
                    finC.pop(); finC.append(C.at(i + 3))
                    del blinker[cur:cur + 1]
                    st["num_comb"] += 1
            elif prenear > postnear and postnear <= pix_comb:
                if blinker.at(cur + 1) == 0:  # merge with the next fixation
                    if P.at(i + 7) - P.at(i + 2) >= ms_comb:
                        keep(i, src=i + 4, start=P.at(i + 2)); del blinker[cur:cur + 1]; i += 4
                    elif abs(P.at(i + 4) - P.at(i + 8)) <= pix_comb:
                        keep(i, src=i + 4, start=P.at(i + 2), end=P.at(i + 11)); del blinker[cur:cur + 2]; i += 8
                    else:
                        keep(i, src=i + 4, start=P.at(i + 2)); del blinker[cur:cur + 1]; i += 4
                    st["num_comb"] += 1
                else:
                    keep(i)
            else:
                keep(i)
        else:
            keep(i)
        i += 4
    # exclusion: blink or long fixation on, before or after any fixation on the critical region
    cs, ce = st["crit"]
    for k in range(1, len(finP) - 1, 4):
        f = (k + 3) // 4
        if cs <= finC.at(k) < ce:
            if 1 in (blinker.at(f), blinker.at(f - 1), blinker.at(f + 1)):
                st["cond"] = 99
                break
            if max(finP.at(k + 3) - finP.at(k + 2), finP.at(k - 1) - finP.at(k - 2), finP.at(k + 7) - finP.at(k + 6)) > longcut:
                st["cond"] = 98
                break
    st["finP"], st["finC"] = finP, finC


# --------------------------------------------------------------------------------------------------------------------
# EyeDry
# --------------------------------------------------------------------------------------------------------------------

_SPACE = frozenset(b" \t\n\v\f\r")


class _EyeDryBuffer:
    """EyeDry's global line buffer (``char buff[4000]``) read with fgets(), atoi() and movenextnumber()."""

    def __init__(self):
        # past the 4000 bytes, the original program read whatever followed in memory; " 0 0 0" makes those reads 0
        self.buf = bytearray(4000) + bytearray(b" 0" * 4000)

    def fgets(self, line: str):
        b = line.encode("latin-1")[:3999]
        self.buf[:len(b) + 1] = b + b"\0"

    def atoi(self, p):
        while self.buf[p] in _SPACE:
            p += 1
        sign = 1
        if self.buf[p] in b"+-":
            sign = -1 if self.buf[p] == ord("-") else 1
            p += 1
        v = 0
        while 48 <= self.buf[p] <= 57:
            v = v * 10 + self.buf[p] - 48
            p += 1
        return sign * v

    def field(self, n):
        """spacebuff(): position just before the n-th whitespace-separated field (n >= 2)."""
        j = 0
        for _ in range(n - 1):
            while self.buf[j] in _SPACE:
                j += 1
            while self.buf[j] not in _SPACE:
                j += 1
            while self.buf[j] in _SPACE:
                j += 1
        return j - 1

    def movenextnumber(self, p):
        while self.buf[p] in _SPACE:
            if self.buf[p] == ord("\n"):
                return p
            p += 1
        while self.buf[p] not in _SPACE and p < len(self.buf) - 1:  # '\0' is not a space: runs into old text
            p += 1
        while self.buf[p] in _SPACE:
            p += 1
        return p


def eyedry_read_fixations(da1_lines, overrun: bool = False) -> pl.DataFrame:
    """Fixations (x, y, start, end) per trial as EyeDry reads them from .da1 lines (one subject or several).

    EyeDry reads as many fixations as column 8 says. Tim10drop writes a count there that includes fixations made
    after the button press, which are not written to the line. With ``overrun=True`` the extra fixations are read
    the way EyeDry did: from text that earlier, longer lines left in the buffer after the end of the current line.
    """
    buf = _EyeDryBuffer()
    rows = []
    for seq_line, line in enumerate(da1_lines):
        buf.fgets(line)
        fields = line.split()
        cond, item = int(fields[1]), int(fields[2])
        n_written = (len(fields) - 8) // 4
        n_read = buf.atoi(buf.field(8)) if overrun else n_written
        p = buf.field(9)
        for k in range(n_read):
            vals = []
            for _ in range(4):
                vals.append(buf.atoi(p))
                p = buf.movenextnumber(p)
            rows.append(dict(line_no=seq_line, item=item, cond=cond, fix=k + 1, x=vals[0], y=vals[1],
                             start=vals[2], end=vals[3], phantom=k >= n_written))
    schema = dict(line_no=pl.Int64, item=pl.Int64, cond=pl.Int64, fix=pl.Int64, x=pl.Int64, y=pl.Int64,
                  start=pl.Int64, end=pl.Int64, phantom=pl.Boolean)
    return pl.DataFrame(rows, schema=schema)


def _region_measures(fix, start, end):
    """EyeDry's ff(), fp(), go_past() and tt() for one region; fix = [(position, duration), ...]."""
    ffd = None
    for pos, dur in fix:
        if pos >= end and dur > SHORT_TIME:  # went past the region (skipped)
            break
        if start <= pos < end:
            if dur > LONG_TIME:
                break
            if dur > SHORT_TIME:
                ffd = dur
                break
    v = nv = 0  # first pass (gaze duration)
    for pos, dur in fix:
        if pos >= end and dur > SHORT_TIME:
            break
        if pos < start and nv:  # regression out of the region ends first pass (also a short fixation)
            break
        if start <= pos < end:
            if dur > LONG_TIME:
                v = nv = 0
                break
            if dur > SHORT_TIME:
                v, nv = v + dur, nv + 1
                if v > GD_CUTOFF:
                    v = nv = 0
                    break
    gd = v if nv else None
    v = nv = 0  # go-past: from entering the region until a fixation to its right
    entered = False
    for pos, dur in fix:
        entered = entered or start <= pos < end
        if pos >= end and dur > SHORT_TIME:
            break
        if entered and pos < end:
            if dur > LONG_TIME:
                v = nv = 0
                break
            if dur > SHORT_TIME:
                v, nv = v + dur, nv + 1
    gp = v if nv else None
    v = nv = 0  # total viewing time
    for pos, dur in fix:
        if start <= pos < end:
            if dur > LONG_TIME:
                break
            if dur > SHORT_TIME:
                v, nv = v + dur, nv + 1
                if v > TVT_CUTOFF:
                    v = nv = 0
                    break
    tvt = v if nv else None
    return ffd, gd, gp, tvt


def eyedry_measures(fixations: pl.DataFrame, regions: pl.DataFrame, group_cols=("subj", "item", "cond")) -> pl.DataFrame:
    """FFD, GD, go-past and TVT per trial and region, computed like EyeDry (analyses 1, 2, 13 and 3).

    ``fixations`` needs the group columns and ``x`` (character), ``y`` (line; -1 = off the text), ``start``, ``end``.
    Conditions other than 1 and 2 (excluded trials) are skipped. Missing values mean "no valid observation".
    """
    starts = {k: d.sort("region")["char_start"].to_list() for k, d in regions.group_by(["item", "cond"])}
    rows = []
    fx = fixations.filter(pl.col("cond").is_in([1, 2])).sort([*group_cols, "fix"])
    for key, d in fx.group_by(list(group_cols), maintain_order=True):
        key = dict(zip(group_cols, key))
        seq = [(x + SCREEN_WIDTH_CHARS * y, e - s)
               for x, y, s, e in d.select("x", "y", "start", "end").iter_rows() if 0 <= y < 1]
        st = starts[(key["item"], key["cond"])]
        for r, a in enumerate(st):
            b = st[r + 1] if r + 1 < len(st) else a + 20  # EyeDry: the last region is 20 characters long
            ffd, gd, gp, tvt = _region_measures(seq, a, b)
            rows.append(dict(key, region=r + 1, FFD=ffd, GD=gd, GP=gp, TVT=tvt))
    return pl.DataFrame(rows, schema_overrides=dict(FFD=pl.Int64, GD=pl.Int64, GP=pl.Int64, TVT=pl.Int64))


# --------------------------------------------------------------------------------------------------------------------
# Whole experiment, original files
# --------------------------------------------------------------------------------------------------------------------

def subject_files(edf_dir: Path = EDF_DIR) -> list[str]:
    """The 30 participants in the order EyeDry numbered them (da1new.lst)."""
    return [l.strip()[:-4] for l in open(edf_dir / "da1new.lst") if l.strip()]


def process_subject(name: str, regions: pl.DataFrame, edf_dir: Path = EDF_DIR) -> dict:
    gaze = load_recording(edf_dir / f"{name}.asc")
    trials, fixations, da1 = doctor_recording(gaze, regions)
    questions = trials_from_messages(gaze.messages).filter(pl.col("type").is_in(["F", "P"]) & pl.col("correct_button").is_not_null())
    return dict(gaze=gaze, trials=trials, fixations=fixations, da1=da1, questions=questions)


def process_all(cache_dir: Path = DATA_DIR / "derived", edf_dir: Path = EDF_DIR, verbose: bool = True) -> dict:
    """Run load_recording + doctor_recording for all participants; results are cached as parquet files."""
    cache_dir = Path(cache_dir)
    names = ["trials", "fixations", "da1", "questions", "raw_fixations"]
    if all((cache_dir / f"{n}.parquet").exists() for n in names):
        return {n: pl.read_parquet(cache_dir / f"{n}.parquet") for n in names}
    patch_eyelink_event_parsing()
    regions = read_regions(edf_dir / "frases_c.cnt")
    out = {n: [] for n in names}
    for subj, name in enumerate(subject_files(edf_dir), start=1):
        if verbose:
            print(f"{subj:2d} {name}", flush=True)
        r = process_subject(name, regions, edf_dir)
        tag = [pl.lit(subj).alias("subj"), pl.lit(name).alias("file")]
        out["trials"].append(r["trials"].with_columns(tag))
        out["fixations"].append(r["fixations"].with_columns(tag))
        out["da1"].append(pl.DataFrame({"line": r["da1"]}).with_row_index("line_no").with_columns(tag))
        out["questions"].append(r["questions"].with_columns(tag))
        out["raw_fixations"].append(fixations_from_gaze(r["gaze"]).with_columns(tag))
    cache_dir.mkdir(parents=True, exist_ok=True)
    res = {}
    for n in names:
        res[n] = pl.concat(out[n], how="diagonal_relaxed")
        res[n].write_parquet(cache_dir / f"{n}.parquet")
    return res


def read_da1(path: Path) -> list[str]:
    return open(path, newline="").readlines()


def read_ixs(path: Path, measure: str) -> pl.DataFrame:
    """Original EyeDry output (wide, one column per region) in long format."""
    d = (pl.read_csv(path, infer_schema_length=0)
           .with_columns(pl.all().cast(pl.Float64).cast(pl.Int64))
           .filter(pl.col("cond") != 0))
    return (d.unpivot(index=["seq", "subj", "item", "cond"], on=[c for c in d.columns if c.startswith("R")],
                      variable_name="region", value_name=measure)
             .with_columns(pl.col("region").str.slice(1).cast(pl.Int64)).drop("seq")
             .filter(pl.col("region") <= 6))
