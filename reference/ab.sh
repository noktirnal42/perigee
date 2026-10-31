#!/bin/bash
# usage: ab.sh <label>   -- 30s router ping @0.2s, reports loss/p95/max and stall episodes
LABEL="${1:-test}"
GW=$(route -n get default 2>/dev/null | awk '/gateway:/{print $2}')
IF=$(route -n get default 2>/dev/null | awk '/interface:/{print $2}')
OUT=$(mktemp)
ping -i 0.2 -c 150 "$GW" > "$OUT" 2>&1
python3 -I - "$OUT" "$LABEL" "$GW" "$IF" <<'EOF'
import re,sys,statistics as st
f,label,gw,iface=sys.argv[1:5]
pts=[(int(m[1]),float(m[2])) for l in open(f) if (m:=re.search(r'icmp_seq=(\d+).*time=([\d.]+)',l))]
N=150; got={s for s,_ in pts}; v=[t for _,t in pts]
bad=sorted([s*0.2 for s,t in pts if t>20]+[s*0.2 for s in range(N) if s not in got])
ep=[]
for t in bad:
    if ep and t-ep[-1][-1]<=1.0: ep[-1].append(t)
    else: ep.append([t])
starts=[e[0] for e in ep]
gaps=[round(b-a,1) for a,b in zip(starts,starts[1:])]
print("[%s] via %s -> %s"%(label,iface,gw))
print("  loss %.1f%%  median %.1fms  p95 %.1fms  max %.1fms  stall-episodes %d  avg gap %s"%(
  100*(N-len(v))/N, st.median(v), sorted(v)[int(len(v)*.95)], max(v), len(ep),
  ("%.1fs"%st.mean(gaps)) if gaps else "n/a"))
EOF
rm -f "$OUT"
