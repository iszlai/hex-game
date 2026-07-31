#!/usr/bin/env python3
"""The asset desk, in a browser.

A dev tool. It lives in `tools/`, which no export preset ships, and the game
neither knows nor cares that it exists.

`make assets` answers "what is missing" in a terminal, which is the right shape
for a checklist and the wrong shape for *looking* at six paintings and deciding
which chapter each belongs to. This shows them.

It reads `tools/asset_manifest.json` — the same file the GDScript checker reads,
because two copies of "what the game wants" is one copy that quietly stops being
true.

Standard library only: no pip, no node, no build step. A dev tool that needs
installing is a dev tool nobody runs.

    python3 tools/asset_server.py [port]
"""

import http.server
import json
import mimetypes
import os
import shutil
import socketserver
import struct
import sys
import urllib.parse

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MANIFEST = os.path.join(ROOT, "tools", "asset_manifest.json")


def manifest():
    with open(MANIFEST, encoding="utf-8") as f:
        return json.load(f)


def png_size(path):
    """Width and height from the IHDR header, without decoding the image."""
    try:
        with open(path, "rb") as f:
            head = f.read(24)
        if len(head) < 24 or head[1:4] != b"PNG":
            return None
        return struct.unpack(">II", head[16:24])
    except OSError:
        return None


def status():
    data = manifest()
    rows = []
    total = 0
    for spec in data["assets"]:
        full = os.path.join(ROOT, spec["path"])
        here = os.path.isfile(full)
        size = os.path.getsize(full) if here else 0
        total += size
        got = png_size(full) if here and spec["kind"] == "image" else None
        want = spec.get("want", [0, 0])
        rows.append({
            **spec,
            "here": here,
            "bytes": size,
            "width": got[0] if got else 0,
            "height": got[1] if got else 0,
            # Advice, never a gate: a picture smaller than ideal should land with a
            # warning rather than be refused.
            "small": bool(got and (got[0] < want[0] or got[1] < want[1])),
        })

    groups = []
    for spec in data["groups"]:
        folder = os.path.join(ROOT, spec["dir"])
        found = 0
        if os.path.isdir(folder):
            found = len([f for f in os.listdir(folder) if f.endswith(spec["ext"])])
            total += sum(os.path.getsize(os.path.join(folder, f))
                         for f in os.listdir(folder) if not f.endswith(".import"))
        groups.append({**spec, "found": found})

    return {"assets": rows, "groups": groups, "bytes": total,
            "extensions": data["extensions"]}


class Desk(http.server.BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass  # the terminal is for the one line that says where to point a browser

    def _send(self, code, body, kind="application/json"):
        if isinstance(body, str):
            body = body.encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", kind)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _spec(self, role):
        for spec in manifest()["assets"]:
            if spec["role"] == role:
                return spec
        return None

    def do_GET(self):
        url = urllib.parse.urlparse(self.path)
        query = urllib.parse.parse_qs(url.query)

        if url.path == "/":
            return self._send(200, PAGE, "text/html; charset=utf-8")
        if url.path == "/api/assets":
            return self._send(200, json.dumps(status()))
        if url.path == "/api/file":
            spec = self._spec(query.get("role", [""])[0])
            if not spec:
                return self._send(404, b"", "text/plain")
            full = os.path.join(ROOT, spec["path"])
            if not os.path.isfile(full):
                return self._send(404, b"", "text/plain")
            with open(full, "rb") as f:
                body = f.read()
            kind = mimetypes.guess_type(full)[0] or "application/octet-stream"
            return self._send(200, body, kind)
        return self._send(404, b"", "text/plain")

    def do_POST(self):
        url = urllib.parse.urlparse(self.path)
        query = urllib.parse.parse_qs(url.query)
        if url.path != "/api/upload":
            return self._send(404, b"", "text/plain")

        role = query.get("role", [""])[0]
        name = query.get("name", ["file"])[0]
        spec = self._spec(role)
        if not spec:
            return self._send(400, json.dumps({"error": "no such role: %s" % role}))

        ext = os.path.splitext(name)[1].lower()
        wanted = os.path.splitext(spec["path"])[1].lower()
        if ext != wanted:
            # The role decides the name, so a mismatch is refused rather than
            # written under a name the game will never look for.
            return self._send(400, json.dumps({
                "error": "%s is loaded as %s — that file is %s" % (role, wanted, ext)}))

        body = self.rfile.read(int(self.headers.get("Content-Length", 0)))
        full = os.path.join(ROOT, spec["path"])
        os.makedirs(os.path.dirname(full), exist_ok=True)
        replacing = os.path.isfile(full)
        # Written beside the target and renamed over it: a half-written PNG is a
        # broken asset, and the game may be running while this happens.
        tmp = full + ".uploading"
        with open(tmp, "wb") as f:
            f.write(body)
        shutil.move(tmp, full)
        return self._send(200, json.dumps({
            "ok": True, "replaced": replacing, "path": spec["path"],
            "bytes": len(body)}))


PAGE = r"""<!doctype html>
<meta charset="utf-8">
<title>Hexflow — assets</title>
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
  :root {
    --ground:#16110c; --panel:#221a12; --panel-2:#2b2118;
    --rule:#3b3025; --ink:#f0e6d4; --ink-2:#b0a18c; --ink-3:#857868;
    --timber:#c39a6b; --ok:#7fe8e0; --want:#f0a830; --warn:#e2705a;
    --mono:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;
    --sans:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif;
  }
  * { box-sizing:border-box }
  body { margin:0; background:var(--ground); color:var(--ink);
         font-family:var(--sans); font-size:15px; line-height:1.5 }
  header { padding:28px 32px 20px; border-bottom:2px solid var(--timber) }
  h1 { margin:0 0 6px; font-family:var(--mono); font-size:24px; font-weight:600;
       letter-spacing:-.01em }
  .sub { color:var(--ink-2); font-size:14px }
  .sub b { color:var(--want); font-weight:600 }
  main { padding:24px 32px 80px; display:grid; gap:14px;
         grid-template-columns:repeat(auto-fill,minmax(320px,1fr)) }
  .card { background:var(--panel); border:1px solid var(--rule); border-radius:4px;
          overflow:hidden; display:flex; flex-direction:column }
  .card.drag { border-color:var(--want); background:var(--panel-2) }
  .thumb { height:130px; background:var(--panel-2); display:flex; align-items:center;
           justify-content:center; border-bottom:1px solid var(--rule); position:relative }
  .thumb img { width:100%; height:100%; object-fit:cover; display:block }
  .thumb .none { font-family:var(--mono); font-size:11px; letter-spacing:.14em;
                 text-transform:uppercase; color:var(--ink-3) }
  .body { padding:12px 14px 14px; display:flex; flex-direction:column; gap:6px; flex:1 }
  .role { font-family:var(--mono); font-size:13px; font-weight:600 }
  .note { color:var(--ink-2); font-size:13px }
  .meta { font-family:var(--mono); font-size:11.5px; color:var(--ink-3);
          font-variant-numeric:tabular-nums }
  .meta.small { color:var(--warn) }
  .pill { font-family:var(--mono); font-size:10px; letter-spacing:.1em;
          text-transform:uppercase; padding:2px 7px; border-radius:2px;
          position:absolute; top:8px; right:8px }
  .pill.here { color:var(--ground); background:var(--ok) }
  .pill.gone { color:var(--ground); background:var(--want) }
  .pill.mat  { color:var(--ground); background:var(--timber); right:auto; left:8px }
  .row { display:flex; gap:8px; align-items:center; margin-top:auto; padding-top:8px }
  button, label.btn { font-family:var(--mono); font-size:12px; cursor:pointer;
          background:var(--panel-2); color:var(--ink); border:1px solid var(--rule);
          border-radius:3px; padding:6px 10px }
  button:hover, label.btn:hover { border-color:var(--timber); color:var(--timber) }
  audio { width:100%; height:32px }
  input[type=file] { display:none }
  .groups { margin:28px 32px 0; border-top:1px solid var(--rule); padding-top:18px }
  .groups h2 { font-family:var(--mono); font-size:11px; letter-spacing:.16em;
               text-transform:uppercase; color:var(--timber); margin:0 0 10px }
  .grp { display:flex; gap:12px; align-items:baseline; padding:7px 0;
         border-bottom:1px solid var(--panel-2) }
  .grp .n { font-family:var(--mono); font-size:13px; min-width:90px }
  .grp .c { font-family:var(--mono); font-size:12px; min-width:90px;
            font-variant-numeric:tabular-nums }
  .grp .c.part { color:var(--want) }
  .grp .d { color:var(--ink-2); font-size:13px }
  #toast { position:fixed; left:50%; bottom:28px; transform:translateX(-50%);
           background:var(--panel-2); border:1px solid var(--timber); color:var(--ink);
           font-family:var(--mono); font-size:13px; padding:10px 18px; border-radius:3px;
           opacity:0; transition:opacity .2s; pointer-events:none }
  #toast.on { opacity:1 }
  #toast.bad { border-color:var(--warn); color:var(--warn) }
</style>

<header>
  <h1>Hexflow — assets</h1>
  <div class="sub" id="summary">reading…</div>
</header>
<main id="grid"></main>
<div class="groups"><h2>Counted groups</h2><div id="groups"></div></div>
<div id="toast"></div>

<script>
const grid = document.getElementById('grid');
const toastEl = document.getElementById('toast');
let toastTimer;

function toast(text, bad) {
  toastEl.textContent = text;
  toastEl.className = 'on' + (bad ? ' bad' : '');
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => toastEl.className = '', 2600);
}

function kb(n) {
  return n >= 1048576 ? (n / 1048576).toFixed(1) + ' MB' : Math.round(n / 1024) + ' KB';
}

async function load() {
  const data = await (await fetch('/api/assets')).json();
  grid.innerHTML = '';
  const missing = data.assets.filter(a => !a.here).map(a => a.role);

  for (const a of data.assets) {
    const card = document.createElement('div');
    card.className = 'card';

    // Thumb: the picture itself, or the track, or a placeholder.
    let thumb = '<div class="none">not here yet</div>';
    if (a.here && a.kind === 'image') {
      thumb = `<img src="/api/file?role=${a.role}&v=${Date.now()}" alt="">`;
    } else if (a.here) {
      thumb = `<div class="none">audio</div>`;
    }
    const size = a.here
      ? (a.kind === 'image' ? `${a.width}×${a.height} · ${kb(a.bytes)}` : kb(a.bytes))
      : `wants ${a.want[0]}×${a.want[1]}`;

    card.innerHTML = `
      <div class="thumb">
        ${thumb}
        <span class="pill ${a.here ? 'here' : 'gone'}">${a.here ? 'here' : 'wanted'}</span>
        ${a.material ? '<span class="pill mat">neutral</span>' : ''}
      </div>
      <div class="body">
        <div class="role">${a.role}</div>
        <div class="note">${a.note}</div>
        <div class="meta ${a.small ? 'small' : ''}">${size}${a.small ? ' · under the asked size' : ''}</div>
        ${a.here && a.kind === 'audio'
          ? `<audio controls preload="none" src="/api/file?role=${a.role}"></audio>` : ''}
        <div class="row">
          <label class="btn">${a.here ? 'replace' : 'add'}
            <input type="file" data-role="${a.role}">
          </label>
          <span class="meta">or drop a file here</span>
        </div>
      </div>`;

    // Drag and drop onto the card it belongs to, which is the whole reason this
    // exists rather than a flag on a command line.
    card.addEventListener('dragover', e => { e.preventDefault(); card.classList.add('drag'); });
    card.addEventListener('dragleave', () => card.classList.remove('drag'));
    card.addEventListener('drop', e => {
      e.preventDefault();
      card.classList.remove('drag');
      if (e.dataTransfer.files[0]) upload(a.role, e.dataTransfer.files[0]);
    });
    card.querySelector('input').addEventListener('change', e => {
      if (e.target.files[0]) upload(a.role, e.target.files[0]);
    });
    grid.appendChild(card);
  }

  document.getElementById('summary').innerHTML =
    `${data.assets.filter(a => a.here).length} of ${data.assets.length} files present · `
    + `${kb(data.bytes)} on disk`
    + (missing.length ? ` · still wanted: <b>${missing.join(', ')}</b>` : ' · nothing missing');

  document.getElementById('groups').innerHTML = data.groups.map(g => `
    <div class="grp">
      <span class="n">${g.role}</span>
      <span class="c ${g.found < g.want ? 'part' : ''}">${g.found} of ${g.want}</span>
      <span class="d">${g.note}</span>
    </div>`).join('');
}

async function upload(role, file) {
  const url = `/api/upload?role=${encodeURIComponent(role)}&name=${encodeURIComponent(file.name)}`;
  const res = await fetch(url, { method: 'POST', body: file });
  const out = await res.json();
  if (!res.ok) return toast(out.error, true);
  toast(`${out.replaced ? 'replaced' : 'added'} ${out.path} — run make import`);
  load();
}

load();
</script>
"""


def main():
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 7777
    socketserver.TCPServer.allow_reuse_address = True
    with socketserver.TCPServer(("127.0.0.1", port), Desk) as httpd:
        print("asset desk: http://127.0.0.1:%d   (ctrl-c to stop)" % port)
        print("files land in %s — run `make import` after, then commit them" % ROOT)
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("")


if __name__ == "__main__":
    main()
