"""Records a Dart VM timeline from a running profile build and lists what the
slow frames (>16.7 ms build) spent their time on (docs/PERFORMANCE.md).

  python tool/perf/trace.py <vm-service-http-uri> <seconds> <out.json>
"""
import json, sys, time, collections
import websocket

uri, secs, out = sys.argv[1], int(sys.argv[2]), sys.argv[3]
ws_uri = uri.replace('http://', 'ws://').rstrip('/') + '/ws'
ws = websocket.create_connection(ws_uri, timeout=120)
_id = 0
def call(method, **params):
    global _id
    _id += 1
    ws.send(json.dumps({'jsonrpc': '2.0', 'id': str(_id), 'method': method, 'params': params}))
    while True:
        m = json.loads(ws.recv())
        if m.get('id') == str(_id):
            if 'error' in m: raise RuntimeError(m['error'])
            return m['result']

call('setVMTimelineFlags', recordedStreams=['Dart', 'Embedder', 'GC'])
call('clearVMTimeline')
# The VM keeps a small ring buffer (about 1.5 s with per-widget build
# events), so pull and clear it in short chunks.
events, end = [], time.time() + secs
while time.time() < end:
    time.sleep(0.5)
    events += call('getVMTimeline')['traceEvents']
    call('clearVMTimeline')
json.dump({'traceEvents': events}, open(out, 'w'))

# Pair B/E events per thread into spans.
spans, stack = [], collections.defaultdict(list)
for e in sorted((e for e in events if e.get('ph') in ('B', 'E', 'X')), key=lambda e: e['ts']):
    if e['ph'] == 'X':
        spans.append((e['name'], e['ts'], e['ts'] + e.get('dur', 0), e['tid']))
    elif e['ph'] == 'B':
        stack[e['tid']].append(e)
    elif stack[e['tid']]:
        b = stack[e['tid']].pop()
        spans.append((b['name'], b['ts'], e['ts'], e['tid']))

frames = [s for s in spans if s[0] in ('Animator::BeginFrame', 'BUILD', 'Frame') and s[2] - s[1] > 16000]
frames = [s for s in spans if s[0] == 'Animator::BeginFrame' and s[2] - s[1] > 16000] or frames
print(f'{len(frames)} slow UI frames')
for name, t0, t1, tid in frames[:40]:
    inner = [s for s in spans if s[3] == tid and s[1] >= t0 and s[2] <= t1 and s[0] != name]
    agg = collections.Counter()
    for n, a, b, _ in inner:
        agg[n] += b - a
    top = ', '.join(f'{n} {d/1000:.1f}' for n, d in agg.most_common(14))
    print(f'-- {(t1-t0)/1000:.1f}ms: {top}')
