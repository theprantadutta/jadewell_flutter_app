"""Ranks the app's own widgets by self build time inside slow BUILD phases of
a trace recorded by trace.py (docs/PERFORMANCE.md).

  python tool/perf/top_widgets.py build/perf/trace.json [min_build_ms=12]
"""
import json, sys, collections, glob, re, os

root = os.path.join(os.path.dirname(__file__), '..', '..', 'lib')
app = set()
for f in glob.glob(os.path.join(root, '**', '*.dart'), recursive=True):
    app.update(re.findall(r'^class (\w+)', open(f, encoding='utf-8').read(), re.M))

ev = [e for e in json.load(open(sys.argv[1]))['traceEvents'] if e.get('ph') in ('B', 'E')]
min_us = float(sys.argv[2] if len(sys.argv) > 2 else 12) * 1000
ev.sort(key=lambda e: e['ts'])
stack, spans = collections.defaultdict(list), []
for e in ev:
    st = stack[e['tid']]
    if e['ph'] == 'B':
        st.append([e['name'], e['ts'], 0])  # name, start, time in nested app widgets
        continue
    for k in range(len(st) - 1, -1, -1):
        if st[k][0] == e['name']:
            name, t0, nested = st.pop(k)
            dur = e['ts'] - t0
            if name in app:
                spans.append((name, t0, e['ts'], e['tid'], dur - nested))
                for p in reversed(st[:k]):  # charge the nearest app ancestor
                    if p[0] in app:
                        p[2] += dur
                        break
            elif name == 'BUILD':
                spans.append(('BUILD', t0, e['ts'], e['tid'], dur))
            break

builds = [s for s in spans if s[0] == 'BUILD' and min_us < s[2] - s[1] < 400000]
total = collections.Counter(); count = collections.Counter()
for _, t0, t1, tid, _ in builds:
    for n, a, b, t, self_us in spans:
        if t == tid and a >= t0 and b <= t1 and n != 'BUILD':
            total[n] += self_us; count[n] += 1
    inner = collections.Counter()
    for n, a, b, t, self_us in spans:
        if t == tid and a >= t0 and b <= t1 and n != 'BUILD':
            inner[n] += self_us
    print(f'-- BUILD {(t1 - t0) / 1000:.1f} ms: ' + ', '.join(f'{n} {d / 1000:.1f}' for n, d in inner.most_common(8)))
print(f'\n{len(builds)} slow builds; app widgets by total self time:')
for n, d in total.most_common(25):
    print(f'{d / 1000:8.1f} ms  x{count[n]:<5} {n}')
