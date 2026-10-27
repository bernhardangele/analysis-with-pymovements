#!/bin/bash
# Compile the original EyeDry (sources/eyedry.c) and run the four analyses used for the frases-comas paper
# (FFD = analysis 1, GD = 2, go-past = 13, TVT = 3) on
#   original/   the .da1 files as written by Tim10drop.pl
#   corrected/  the same files with column 8 (number of fixations) set to the number of fixations on the line
# Output: IXS files in $OUT/original and $OUT/corrected (default: /tmp/eyedry).
#
# Changes needed to build the 2011 source with a current gcc (behaviour is unchanged):
#   - gets() no longer exists: replaced by a fgets() wrapper (shim.h)
#   - char is unsigned on ARM: -fsigned-char, otherwise `while ((c = fgetc(f)) != EOF)` never ends
#   - buff[] is extended by a tail of " 0" tokens: EyeDry reads past the end of a line (see the slides); on the
#     original Windows build, reads past the 4000-byte buffer returned whatever followed in memory
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
EDF="$ROOT/workshop/data/frases-comas/edf"
OUT="${OUT:-/tmp/eyedry}"
mkdir -p "$OUT/original" "$OUT/corrected"

sed -e 's/^void main()/int main()/' -e 's/^char buff\[MAXLINEX\];/char buff[3*MAXLINEX];/' "$ROOT/sources/eyedry.c" \
  | python3 -c '
import sys
s = sys.stdin.read()
i = s.index("{", s.index("int main()")) + 1
s = s[:i] + "\n{ int k; for(k=MAXLINEX;k<3*MAXLINEX-1;k++) buff[k] = (k%2) ? (char)48 : (char)32; buff[3*MAXLINEX-1]=0; }\n" + s[i:]
sys.stdout.write(s)' > "$OUT/eyedry.c"
gcc -O0 -w -std=gnu89 -fsigned-char -include "$HERE/shim.h" -o "$OUT/eyedry" "$OUT/eyedry.c" -lm

cp "$EDF"/*.da1 "$EDF/frases_c.cnt" "$EDF/commas.ctl" "$EDF/da1new.lst" "$OUT/original/"
cp "$EDF/frases_c.cnt" "$EDF/commas.ctl" "$EDF/da1new.lst" "$OUT/corrected/"
python3 - "$EDF" "$OUT/corrected" <<'EOF'
import sys, glob, os
src, dst = sys.argv[1:]
for f in glob.glob(os.path.join(src, "*.da1")):
    out = []
    for line in open(f, newline=""):
        p = line.rstrip("\n").rstrip("\t").split("\t")
        p[7] = " " + str((len(p) - 8) // 4)
        out.append("\t".join(p) + "\t\n")
    open(os.path.join(dst, os.path.basename(f)), "w", newline="").write("".join(out))
EOF

run() {  # dir, answers...
  local d=$1; shift
  (cd "$d" && printf '%s\n' "$@" | "$OUT/eyedry" > /dev/null 2>&1 || true)
}
for d in "$OUT/original" "$OUT/corrected"; do
  common=(trace.tr frases-comas "" commas.ctl "" da1new.lst n frases_c.cnt)
  tail=(a w "" "" "" "" n 0 0 0)
  run "$d" "${common[@]}" 1 FFD 1 r n n n FFDW.IXS "${tail[@]}"
  run "$d" "${common[@]}" 2 GD y c r n n "" n GD.IXS "${tail[@]}"
  run "$d" "${common[@]}" 13 GP y c r 1 GOPAST.IXS "${tail[@]}"
  run "$d" "${common[@]}" 3 TVT y c r n n "" n TVT.IXS "${tail[@]}"
done

for f in FFDW GD GOPAST TVT; do
  n=$(diff <(tr -d '\r' < "$EDF/$f.IXS") <(tr -d '\r' < "$OUT/original/$f.IXS") | grep -c '^>' || true)
  c=$(diff <(tr -d '\r' < "$OUT/original/$f.IXS") <(tr -d '\r' < "$OUT/corrected/$f.IXS") | grep -c '^>' || true)
  echo "$f.IXS: rebuilt EyeDry differs from the published file in $n lines; corrected .da1 changes $c lines"
done
