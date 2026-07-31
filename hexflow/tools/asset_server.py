#!/usr/bin/env python3
"""The asset desk, in a browser.

A dev tool. It lives in `tools/`, which no export preset ships, and the game
neither knows nor cares that it exists.

`make assets` answers "what is missing" in a terminal, which is the right shape
for a checklist and the wrong shape for *looking* at six paintings and deciding
which chapter each belongs to. This shows them.

Five desks, because the question is a different question each time:

    Art      six backdrops and three surfaces — which painting is which chapter
    Glyphs   §11.4's 52, one tile per file, so "what do I generate" has an answer
    Sound    §15.2's sixteen, each with the brief it was written from, playable
    Type     three families, rendered in the faces themselves at their role sizes
    Colour   §13.2's tokens, edited in place and measured against §21's floors

It reads `tools/asset_manifest.json` — the same file the GDScript checker reads,
because two copies of "what the game wants" is one copy that quietly stops being
true. Where a breakdown already exists somewhere in the project it is **read**
rather than restated: the glyph list comes from `src/data/input_glyphs.json`, the
colour tokens from `src/view/palette.gd`, and the palette checks from the test
that enforces them. A desk that disagreed with the game would be worse than no
desk.

Standard library only: no pip, no node, no build step. A dev tool that needs
installing is a dev tool nobody runs.

    python3 tools/asset_server.py [port]
"""

import http.server
import json
import mimetypes
import os
import re
import shutil
import socketserver
import struct
import sys
import urllib.parse

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MANIFEST = os.path.join(ROOT, "tools", "asset_manifest.json")

## Where the glyph breakdown comes from. §11.4's "52" is 13 slots × 4 families
## *because this file says so* — deriving it is what stops the desk from asking
## for a glyph the game will never look up.
GLYPH_ATLAS = os.path.join("src", "data", "input_glyphs.json")


def manifest():
    with open(MANIFEST, encoding="utf-8") as f:
        return json.load(f)


def read(*parts):
    with open(os.path.join(ROOT, *parts), encoding="utf-8") as f:
        return f.read()


# --- files ---------------------------------------------------------------------

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


def wav_seconds(path):
    """Length of a RIFF/WAVE file, from its two headers.

    Only WAV: an `.ogg` is a container this would have to half-decode, and the
    audio element in the page knows the answer anyway once it is playing.
    """
    try:
        with open(path, "rb") as f:
            head = f.read(12)
            if head[:4] != b"RIFF" or head[8:12] != b"WAVE":
                return None
            rate, channels, bits, frames = 0, 0, 0, 0
            while True:
                chunk = f.read(8)
                if len(chunk) < 8:
                    break
                name, length = chunk[:4], struct.unpack("<I", chunk[4:8])[0]
                body = f.read(length + (length & 1))
                if name == b"fmt " and length >= 16:
                    channels, rate = struct.unpack("<HI", body[2:8])
                    bits = struct.unpack("<H", body[14:16])[0]
                elif name == b"data":
                    frames = length
            if not (rate and channels and bits):
                return None
            return frames / float(rate * channels * bits // 8)
    except (OSError, struct.error):
        return None


def describe(full, kind):
    """What is actually on disk at [full], as far as a checker can tell."""
    here = os.path.isfile(full)
    out = {"here": here, "bytes": os.path.getsize(full) if here else 0,
           "width": 0, "height": 0, "seconds": 0.0}
    if not here:
        return out
    if kind == "image":
        got = png_size(full)
        if got:
            out["width"], out["height"] = got
    elif kind == "audio":
        out["seconds"] = wav_seconds(full) or 0.0
    return out


# --- groups --------------------------------------------------------------------

def glyph_items():
    """§11.4's 52, derived from the atlas the game looks them up in."""
    try:
        atlas = json.loads(read(GLYPH_ATLAS))
    except (OSError, ValueError):
        return []
    out = []
    for family in atlas.get("families", []):
        for slot, label in family.get("labels", {}).items():
            out.append({
                "name": "%s_%s" % (family["name"], slot),
                "family": family["name"],
                "slot": slot,
                "for": slot,
                # The label this glyph replaces. A glyph that shows something else
                # is a glyph that lies about a button, so the desk prints it.
                "make": 'the button the game currently writes as "%s"' % label,
                "label": label,
            })
    return out


def group_items(spec):
    if spec.get("derive") == "glyphs":
        return glyph_items()
    return [dict(item) for item in spec.get("items", [])]


def group_status(spec):
    folder = os.path.join(ROOT, spec["dir"])
    kind = spec.get("kind", "image")
    items = []
    named = set()
    for item in group_items(spec):
        file = item["name"] + spec["ext"]
        named.add(file)
        item.update(describe(os.path.join(folder, file), kind))
        item["path"] = spec["dir"] + file
        items.append(item)

    # Anything in the folder the manifest never asked for. Usually a name typo, and
    # a typo the game will silently ignore is exactly what a desk is for.
    extras, total = [], 0
    if os.path.isdir(folder):
        for file in sorted(os.listdir(folder)):
            if file.endswith(".import"):
                continue
            total += os.path.getsize(os.path.join(folder, file))
            if file.endswith(spec["ext"]) and file not in named:
                extras.append(file)

    out = dict(spec)
    out["items"] = items
    out["extras"] = extras
    out["found"] = sum(1 for i in items if i["here"])
    out["bytes"] = total
    return out


def status():
    data = manifest()
    rows = []
    total = 0
    for spec in data["assets"]:
        full = os.path.join(ROOT, spec["path"])
        found = describe(full, spec["kind"])
        want = spec.get("want", [0, 0])
        total += found["bytes"]
        rows.append({
            **spec, **found,
            # Advice, never a gate: a picture smaller than ideal should land with a
            # warning rather than be refused.
            "small": bool(found["width"] and (found["width"] < want[0]
                                              or found["height"] < want[1])),
        })

    groups = []
    for spec in data["groups"]:
        state = group_status(spec)
        total += state["bytes"]
        groups.append(state)

    return {"assets": rows, "groups": groups, "bytes": total,
            "extensions": data["extensions"]}


# --- colour --------------------------------------------------------------------
#
# Nothing here is restated. The token list is `palette.gd`'s, the values are the
# `.tres` files', and the checks are the ones `test_palette_vision.gd` enforces —
# so the desk can only ever show a floor the build actually holds you to.

TOKEN_RE = re.compile(r'^@export var (\w+): Color = Color\(', re.M)
GROUP_RE = re.compile(r'^@export_group\("([^"]+)"\)')
TRES_RE = re.compile(r'^(\w+) = Color\(([^)]*)\)\s*$')


def colour_tokens():
    """Every token, in declaration order, with the group and doc comment it carries."""
    out, group, doc = [], "", []
    for line in read("src", "view", "palette.gd").splitlines():
        stripped = line.strip()
        found = GROUP_RE.match(stripped)
        if found:
            group, doc = found.group(1), []
            continue
        if stripped.startswith("##"):
            doc.append(stripped[2:].strip())
            continue
        found = TOKEN_RE.match(line)
        if found:
            out.append({"name": found.group(1), "group": group, "doc": " ".join(doc)})
        # A comment only documents what comes *straight* after it.
        doc = []
    return out


def palette_dir():
    return os.path.join(ROOT, manifest()["colour"]["dir"])


def palette_names():
    folder = palette_dir()
    if not os.path.isdir(folder):
        return []
    return sorted(f[:-5] for f in os.listdir(folder) if f.endswith(".tres"))


def palette_path(name):
    """The file for [name], or None. Resolved against the real listing rather than
    joined from the query string, which is the whole of the path-traversal answer."""
    return os.path.join(palette_dir(), name + ".tres") if name in palette_names() else None


def palette_values(name):
    values = {}
    for line in read_file(palette_path(name)).splitlines():
        found = TRES_RE.match(line)
        if found:
            parts = [float(p) for p in found.group(2).split(",")]
            values[found.group(1)] = parts
    return values


def read_file(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


def _num(value):
    """A float the way Godot's own serialiser writes one: `1`, not `1.000000`.

    Matching it matters — the editor rewrites any `.tres` it opens, and a desk that
    wrote a different spelling of the same number would show up as a diff nobody
    made.
    """
    return ("%.6f" % value).rstrip("0").rstrip(".") or "0"


def set_token(name, token, rgba):
    path = palette_path(name)
    if path is None:
        return "no such palette: %s" % name
    if token not in {t["name"] for t in colour_tokens()}:
        return "no such token: %s" % token

    line = "%s = Color(%s)" % (token, ", ".join(_num(v) for v in rgba))
    lines = read_file(path).splitlines()
    for i, existing in enumerate(lines):
        found = TRES_RE.match(existing)
        if found and found.group(1) == token:
            lines[i] = line
            break
    else:
        # A token the palette never overrode, so it was inheriting the default from
        # `palette.gd`. The `[resource]` block runs to the end of the file, so the
        # end of the file is where it belongs.
        lines.append(line)

    # Written beside the target and renamed over it: a half-written `.tres` is a
    # palette the game cannot load, and the game may be running while this happens.
    tmp = path + ".writing"
    with open(tmp, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
    shutil.move(tmp, path)
    return None


def vision_rules():
    """The checks `test_palette_vision.gd` runs, read out of the test itself.

    Parsed rather than copied. A pair the test stopped checking has to stop showing
    up here too, or the desk becomes a second opinion — and §21's whole point is
    that there is one.
    """
    src = read(*manifest()["colour"]["checks"].split("/"))
    which = re.search(r'const FOR := \{(.*?)\n\}', src, re.S)
    rules = {
        "floors": {m.group(1): float(m.group(2))
                   for m in re.finditer(r'^const (MIN_\w+) := ([\d.]+)', src, re.M)},
        "modes": dict(re.findall(r'"(\w+)": "(\w+)"', which.group(1)) if which else []),
        "apart": _pairs_in(src, "_pairs"),
        "greyscale": _pairs_in(src, "_greyscale_pairs"),
        "text": [],
        "text_on": "",
        "unreadable": [],
    }

    # The two checks that are written as their own test rather than as a pair list.
    hatch = re.search(r'_contrast\(palette\.(\w+), palette\.(\w+)\)', src)
    if hatch:
        rules["greyscale"] = rules["greyscale"] + [[hatch.group(1), hatch.group(2)]]
    text = re.search(r'for token: String in \[([^\]]+)\]', src)
    against = re.search(r'palette\.get\(token\) as Color, palette\.(\w+)\)', src)
    if text and against:
        rules["text"] = re.findall(r'"(\w+)"', text.group(1))
        rules["text_on"] = against.group(1)

    for key in ("apart", "greyscale", "modes", "text"):
        if not rules[key]:
            rules["unreadable"].append(key)
    return rules


def _pairs_in(src, function):
    body = re.search(r'func %s\(\) -> Array:\s*\n\treturn \[(.*?)\n\t\]' % function,
                     src, re.S)
    return [list(pair) for pair in
            re.findall(r'\["(\w+)", "(\w+)"\]', body.group(1))] if body else []


def colour():
    return {
        "tokens": colour_tokens(),
        "palettes": [{"name": n, "values": palette_values(n)} for n in palette_names()],
        "rules": vision_rules(),
        "note": manifest()["colour"]["note"],
    }


# --- server --------------------------------------------------------------------

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

    def _group(self, role):
        for spec in manifest()["groups"]:
            if spec["role"] == role:
                return spec
        return None

    def _target(self, query):
        """The one file a request is about, as (project-relative path, wanted extension).

        Both forms resolve through the manifest, so a path only ever comes from
        something the game asked for.
        """
        role = query.get("role", [""])[0]
        spec = self._spec(role)
        if spec:
            return spec["path"], os.path.splitext(spec["path"])[1].lower(), spec
        group = self._group(query.get("group", [""])[0])
        if group is None:
            return None, None, None
        wanted = query.get("item", [""])[0]
        for item in group_items(group):
            if item["name"] == wanted:
                return group["dir"] + wanted + group["ext"], group["ext"], group
        return None, None, None

    def do_GET(self):
        url = urllib.parse.urlparse(self.path)
        query = urllib.parse.parse_qs(url.query)

        if url.path == "/":
            return self._send(200, PAGE, "text/html; charset=utf-8")
        if url.path == "/api/assets":
            return self._send(200, json.dumps(status()))
        if url.path == "/api/colour":
            return self._send(200, json.dumps(colour()))
        if url.path == "/api/file":
            path, _, _ = self._target(query)
            if path is None:
                return self._send(404, b"", "text/plain")
            full = os.path.join(ROOT, path)
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
        body = self.rfile.read(int(self.headers.get("Content-Length", 0)))

        if url.path == "/api/colour":
            return self._colour(body)
        if url.path != "/api/upload":
            return self._send(404, b"", "text/plain")

        path, wanted, spec = self._target(query)
        if path is None:
            return self._send(400, json.dumps({"error": "nothing here wants that file"}))

        name = query.get("name", ["file"])[0]
        ext = os.path.splitext(name)[1].lower()
        if ext != wanted:
            # The slot decides the name, so a mismatch is refused rather than
            # written under a name the game will never look for.
            return self._send(400, json.dumps({
                "error": "%s is loaded as %s — that file is %s"
                         % (os.path.basename(path), wanted, ext or "extensionless")}))

        full = os.path.join(ROOT, path)
        os.makedirs(os.path.dirname(full), exist_ok=True)
        replacing = os.path.isfile(full)
        # Written beside the target and renamed over it: a half-written PNG is a
        # broken asset, and the game may be running while this happens.
        tmp = full + ".uploading"
        with open(tmp, "wb") as f:
            f.write(body)
        shutil.move(tmp, full)
        return self._send(200, json.dumps({
            "ok": True, "replaced": replacing, "path": path, "bytes": len(body),
            "material": bool(spec.get("material", False))}))

    def _colour(self, body):
        try:
            change = json.loads(body or b"{}")
            rgba = [float(v) for v in change["rgba"]]
        except (ValueError, KeyError, TypeError):
            return self._send(400, json.dumps({"error": "expected {palette, token, rgba}"}))
        if len(rgba) != 4:
            return self._send(400, json.dumps({"error": "rgba wants four numbers"}))
        problem = set_token(str(change.get("palette", "")), str(change.get("token", "")), rgba)
        if problem:
            return self._send(400, json.dumps({"error": problem}))
        return self._send(200, json.dumps({"ok": True}))


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
  header { padding:28px 32px 0 }
  h1 { margin:0 0 6px; font-family:var(--mono); font-size:24px; font-weight:600;
       letter-spacing:-.01em }
  .sub { color:var(--ink-2); font-size:14px }
  .sub b { color:var(--want); font-weight:600 }
  nav { display:flex; gap:4px; padding:18px 32px 0; border-bottom:2px solid var(--timber);
        position:sticky; top:0; background:var(--ground); z-index:5; flex-wrap:wrap }
  nav button { font-family:var(--mono); font-size:12px; letter-spacing:.08em;
        text-transform:uppercase; background:none; border:0; border-bottom:2px solid transparent;
        color:var(--ink-3); padding:10px 14px; margin-bottom:-2px; cursor:pointer }
  nav button:hover { color:var(--ink) }
  nav button.on { color:var(--timber); border-bottom-color:var(--timber) }
  nav button .n { font-size:11px; color:var(--ink-3); margin-left:6px }
  nav button.on .n { color:var(--want) }
  section { display:none; padding:24px 32px 90px }
  section.on { display:block }
  .brief { color:var(--ink-2); font-size:13.5px; max-width:76ch; margin:0 0 20px;
           border-left:2px solid var(--rule); padding-left:14px }
  .brief code { font-family:var(--mono); font-size:12.5px; color:var(--timber) }
  h2 { font-family:var(--mono); font-size:11px; letter-spacing:.16em;
       text-transform:uppercase; color:var(--timber); margin:26px 0 10px }
  h2:first-of-type { margin-top:0 }
  .cards { display:grid; gap:14px; grid-template-columns:repeat(auto-fill,minmax(320px,1fr)) }
  .card { background:var(--panel); border:1px solid var(--rule); border-radius:4px;
          overflow:hidden; display:flex; flex-direction:column }
  .card.drag, .tile.drag, .row.drag { border-color:var(--want); background:var(--panel-2) }
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
  .meta.small, .meta.gone { color:var(--warn) }
  .pill { font-family:var(--mono); font-size:10px; letter-spacing:.1em;
          text-transform:uppercase; padding:2px 7px; border-radius:2px;
          position:absolute; top:8px; right:8px }
  .pill.here { color:var(--ground); background:var(--ok) }
  .pill.gone { color:var(--ground); background:var(--want) }
  .pill.mat  { color:var(--ground); background:var(--timber); right:auto; left:8px }
  .row { display:flex; gap:8px; align-items:center; margin-top:auto; padding-top:8px }
  button.act, label.btn { font-family:var(--mono); font-size:12px; cursor:pointer;
          background:var(--panel-2); color:var(--ink); border:1px solid var(--rule);
          border-radius:3px; padding:6px 10px }
  button.act:hover, label.btn:hover { border-color:var(--timber); color:var(--timber) }
  audio { width:100%; height:32px }
  input[type=file] { display:none }

  /* glyphs */
  .fam { margin-bottom:26px }
  .fam h3 { font-family:var(--mono); font-size:13px; margin:0 0 2px; font-weight:600 }
  .fam .d { color:var(--ink-3); font-size:12.5px; margin-bottom:10px }
  .tiles { display:grid; gap:8px; grid-template-columns:repeat(auto-fill,minmax(104px,1fr)) }
  .tile { background:var(--panel); border:1px solid var(--rule); border-radius:4px;
          padding:9px 8px 8px; text-align:center; cursor:pointer }
  .tile .box { height:56px; display:flex; align-items:center; justify-content:center;
               background:var(--panel-2); border-radius:3px; margin-bottom:7px }
  .tile img { width:44px; height:44px; image-rendering:auto }
  .tile .box .none { font-family:var(--mono); font-size:16px; color:var(--want) }
  .tile .s { font-family:var(--mono); font-size:11.5px; color:var(--ink) }
  .tile .l { font-family:var(--mono); font-size:10.5px; color:var(--ink-3);
             white-space:nowrap; overflow:hidden; text-overflow:ellipsis }
  .tile.missing { border-color:var(--want) }

  /* lists */
  .list { display:flex; flex-direction:column; gap:8px }
  .row.item { display:grid; gap:14px; align-items:center; padding:11px 14px;
       grid-template-columns:170px 1fr 190px 128px; background:var(--panel);
       border:1px solid var(--rule); border-radius:4px; margin:0 }
  .row.item .n { font-family:var(--mono); font-size:13px }
  .row.item .n small { display:block; color:var(--ink-3); font-size:11px; letter-spacing:.06em;
       text-transform:uppercase }
  .row.item .m { color:var(--ink-2); font-size:13px }
  .row.item .m em { color:var(--ink-3); font-style:normal }
  .row.item.missing { border-color:var(--want) }
  @media (max-width:960px) { .row.item { grid-template-columns:1fr } }

  /* type */
  .specimen { padding:16px 18px; background:var(--panel-2); border-radius:3px;
              border:1px solid var(--rule); overflow:hidden }
  .specimen div { white-space:nowrap; overflow:hidden; text-overflow:ellipsis; margin:2px 0 }
  .specimen .tag { font-family:var(--mono); font-size:10px; letter-spacing:.12em;
              text-transform:uppercase; color:var(--ink-3) }

  /* colour */
  .palbar { display:flex; gap:6px; flex-wrap:wrap; margin-bottom:18px }
  .palbar button { font-family:var(--mono); font-size:12px; padding:7px 12px; cursor:pointer;
       background:var(--panel); color:var(--ink-2); border:1px solid var(--rule); border-radius:3px }
  .palbar button.on { color:var(--ground); background:var(--timber); border-color:var(--timber) }
  .swatches { display:grid; gap:8px; grid-template-columns:repeat(auto-fill,minmax(230px,1fr)) }
  .sw { display:flex; gap:10px; align-items:center; background:var(--panel);
        border:1px solid var(--rule); border-radius:4px; padding:8px 10px }
  .sw input[type=color] { width:40px; height:40px; padding:0; border:1px solid var(--rule);
        border-radius:3px; background:none; cursor:pointer; flex:none }
  .sw .t { min-width:0 }
  .sw .t b { font-family:var(--mono); font-size:12px; font-weight:600; display:block;
        overflow:hidden; text-overflow:ellipsis }
  .sw .t span { font-family:var(--mono); font-size:11px; color:var(--ink-3) }
  .sw .a { margin-left:auto; font-family:var(--mono); font-size:11px; color:var(--ink-3) }
  .checks { display:flex; flex-direction:column; gap:4px; margin-bottom:22px }
  .chk { display:grid; grid-template-columns:280px 90px 1fr; gap:12px; padding:6px 10px;
         font-family:var(--mono); font-size:12px; background:var(--panel);
         border-left:2px solid var(--ok); border-radius:2px }
  .chk.bad { border-left-color:var(--warn); color:var(--warn) }
  .chk .v { font-variant-numeric:tabular-nums }
  .chk .w { color:var(--ink-3) }
  .chk.bad .w { color:var(--warn) }
  .swatchpair { display:inline-flex; gap:0; vertical-align:middle; margin-right:8px }
  .swatchpair i { width:14px; height:14px; display:block; border:1px solid #0006 }

  #toast { position:fixed; left:50%; bottom:28px; transform:translateX(-50%);
           background:var(--panel-2); border:1px solid var(--timber); color:var(--ink);
           font-family:var(--mono); font-size:13px; padding:10px 18px; border-radius:3px;
           opacity:0; transition:opacity .2s; pointer-events:none; z-index:9 }
  #toast.on { opacity:1 }
  #toast.bad { border-color:var(--warn); color:var(--warn) }
</style>

<header>
  <h1>Hexflow — assets</h1>
  <div class="sub" id="summary">reading…</div>
</header>
<nav id="nav"></nav>
<section id="tab-art" class="on"><div class="cards" id="art"></div></section>
<section id="tab-glyphs"><div class="brief" id="glyph-brief"></div><div id="glyphs"></div></section>
<section id="tab-sfx"><div class="brief" id="sfx-brief"></div><div class="list" id="sfx"></div></section>
<section id="tab-fonts"><div class="brief" id="font-brief"></div><div class="cards" id="fonts"></div></section>
<section id="tab-colour">
  <div class="brief" id="colour-brief"></div>
  <div class="palbar" id="palbar"></div>
  <h2>§21's floors, measured live</h2>
  <div class="checks" id="checks"></div>
  <h2 id="tokens-head">Tokens</h2>
  <div class="swatches" id="swatches"></div>
</section>
<div id="toast"></div>

<script>
const $ = id => document.getElementById(id);
const toastEl = $('toast');
let toastTimer, DATA = null, COLOUR = null, PALETTE = null;

function toast(text, bad) {
  toastEl.textContent = text;
  toastEl.className = 'on' + (bad ? ' bad' : '');
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => toastEl.className = '', 3200);
}

const kb = n => n >= 1048576 ? (n / 1048576).toFixed(1) + ' MB' : Math.round(n / 1024) + ' KB';
const esc = s => String(s).replace(/[&<>"]/g, c =>
  ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]));

// Drop a file onto the thing it belongs to. The whole reason this exists rather
// than a flag on a command line.
function droppable(el, query) {
  el.addEventListener('dragover', e => { e.preventDefault(); el.classList.add('drag'); });
  el.addEventListener('dragleave', () => el.classList.remove('drag'));
  el.addEventListener('drop', e => {
    e.preventDefault();
    el.classList.remove('drag');
    if (e.dataTransfer.files[0]) upload(query, e.dataTransfer.files[0]);
  });
  const input = el.querySelector('input[type=file]');
  if (input) input.addEventListener('change', e => {
    if (e.target.files[0]) upload(query, e.target.files[0]);
  });
}

async function upload(query, file) {
  const url = `/api/upload?${query}&name=${encodeURIComponent(file.name)}`;
  const res = await fetch(url, { method: 'POST', body: file });
  const out = await res.json();
  if (!res.ok) return toast(out.error, true);
  toast(`${out.replaced ? 'replaced' : 'added'} ${out.path} — run make import`
        + (out.material ? ' · this one is a material: the palette colours it' : ''));
  load();
}

// --- tabs ---------------------------------------------------------------------

const TABS = [
  { id: 'art', name: 'Art' },
  { id: 'glyphs', name: 'Glyphs' },
  { id: 'sfx', name: 'Sound' },
  { id: 'fonts', name: 'Type' },
  { id: 'colour', name: 'Colour' },
];

function drawNav(counts) {
  $('nav').innerHTML = TABS.map(t => `
    <button data-tab="${t.id}" class="${t.id === (location.hash.slice(1) || 'art') ? 'on' : ''}">
      ${t.name}<span class="n">${counts[t.id] || ''}</span>
    </button>`).join('');
  $('nav').querySelectorAll('button').forEach(b =>
    b.addEventListener('click', () => show(b.dataset.tab)));
  show(location.hash.slice(1) || 'art');
}

function show(tab) {
  location.hash = tab;
  TABS.forEach(t => $('tab-' + t.id).classList.toggle('on', t.id === tab));
  $('nav').querySelectorAll('button').forEach(b =>
    b.classList.toggle('on', b.dataset.tab === tab));
}

// --- art ----------------------------------------------------------------------

function drawArt(assets) {
  $('art').innerHTML = '';
  for (const a of assets) {
    const card = document.createElement('div');
    card.className = 'card';
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
        <div class="role">${esc(a.role)}</div>
        <div class="note">${esc(a.note)}</div>
        <div class="meta ${a.small ? 'small' : ''}">${size}${a.small ? ' · under the asked size' : ''}</div>
        ${a.here && a.kind === 'audio'
          ? `<audio controls preload="none" src="/api/file?role=${a.role}"></audio>` : ''}
        <div class="row">
          <label class="btn">${a.here ? 'replace' : 'add'}<input type="file"></label>
          <span class="meta">or drop a file here</span>
        </div>
      </div>`;
    droppable(card, `role=${encodeURIComponent(a.role)}`);
    $('art').appendChild(card);
  }
}

// --- glyphs -------------------------------------------------------------------

function drawGlyphs(group) {
  $('glyph-brief').innerHTML = esc(group.note) + ' — ' + esc(group.brief)
    + `<br>Each tile is one file: <code>${esc(group.dir)}&lt;family&gt;_&lt;slot&gt;${group.ext}</code>.`
    + ` The caption under it is the label the game writes today, from`
    + ` <code>src/data/input_glyphs.json</code>.`;

  const families = [];
  for (const item of group.items) {
    let fam = families.find(f => f.name === item.family);
    if (!fam) families.push(fam = { name: item.family, items: [] });
    fam.items.push(item);
  }

  $('glyphs').innerHTML = families.map(f => `
    <div class="fam">
      <h3>${esc(f.name)}</h3>
      <div class="d">${f.items.filter(i => i.here).length} of ${f.items.length} here</div>
      <div class="tiles">${f.items.map(i => `
        <div class="tile ${i.here ? '' : 'missing'}" data-item="${esc(i.name)}"
             title="${esc(i.path)}">
          <div class="box">${i.here
            ? `<img src="/api/file?group=glyphs&item=${encodeURIComponent(i.name)}&v=${Date.now()}" alt="">`
            : '<span class="none">+</span>'}</div>
          <div class="s">${esc(i.slot)}</div>
          <div class="l">${esc(i.label)}</div>
          <input type="file">
        </div>`).join('')}</div>
    </div>`).join('');

  $('glyphs').querySelectorAll('.tile').forEach(tile => {
    const q = `group=glyphs&item=${encodeURIComponent(tile.dataset.item)}`;
    droppable(tile, q);
    tile.addEventListener('click', () => tile.querySelector('input').click());
  });
}

// --- sound --------------------------------------------------------------------

function drawSfx(group) {
  $('sfx-brief').innerHTML = esc(group.note) + ' — ' + esc(group.brief);
  $('sfx').innerHTML = group.items.map(i => `
    <div class="row item ${i.here ? '' : 'missing'}" data-item="${esc(i.name)}">
      <div class="n">${esc(i.name)}<small>${esc(i.bus)} bus</small></div>
      <div class="m">${esc(i.for)} — <em>${esc(i.make)}</em></div>
      <div>${i.here
        ? `<audio controls preload="none" src="/api/file?group=sfx&item=${encodeURIComponent(i.name)}"></audio>`
        : '<span class="meta gone">no file</span>'}</div>
      <div>
        <div class="meta">${i.here
          ? `${i.seconds ? (i.seconds * 1000).toFixed(0) + ' ms · ' : ''}${kb(i.bytes)}` : ''}</div>
        <label class="btn">${i.here ? 'replace' : 'add'}<input type="file"></label>
      </div>
    </div>`).join('');
  $('sfx').querySelectorAll('.row').forEach(row =>
    droppable(row, `group=sfx&item=${encodeURIComponent(row.dataset.item)}`));
}

// --- type ---------------------------------------------------------------------

const SAMPLE = 'Hexflow — Branches & Portals';

function drawFonts(group) {
  $('font-brief').innerHTML = esc(group.note) + ' — ' + esc(group.brief)
    + ' The specimen below is rendered <b>in the file that is actually on disk</b>,'
    + ' at the px sizes §13.4 gives each role.';
  $('fonts').innerHTML = group.items.map(i => `
    <div class="card" data-item="${esc(i.name)}">
      <div class="body">
        <div class="role">${esc(i.name)}<span class="meta"> · ${esc(i.for)}</span></div>
        <div class="note">${esc(i.make)}</div>
        <div class="specimen" id="spec-${esc(i.name)}">
          ${i.here ? i.roles.map(r => `
            <div class="tag">${esc(r.role)} · ${r.size}px · ${r.weight}</div>
            <div style="font-family:'live-${esc(i.name)}',var(--sans);
                        font-size:${r.size}px; font-weight:${r.weight};
                        line-height:1.15">${esc(SAMPLE)}</div>
            <div style="font-family:'live-${esc(i.name)}',var(--sans);
                        font-size:${r.size}px; font-weight:${r.weight};
                        font-variant-numeric:tabular-nums">0123456789 · 11:11</div>`).join('')
            : '<div class="meta gone">no file — nothing to render</div>'}
        </div>
        <div class="meta">${i.here ? kb(i.bytes) : 'missing'} · licence ${esc(i.licence)}</div>
        <div class="row">
          <label class="btn">${i.here ? 'replace' : 'add'}<input type="file"></label>
          <span class="meta">${esc(i.path)}</span>
        </div>
      </div>
    </div>`).join('');
  $('fonts').querySelectorAll('.card').forEach(card =>
    droppable(card, `group=fonts&item=${encodeURIComponent(card.dataset.item)}`));

  for (const i of group.items) {
    if (!i.here) continue;
    const face = new FontFace('live-' + i.name,
      `url(/api/file?group=fonts&item=${encodeURIComponent(i.name)}&v=${Date.now()})`);
    face.load().then(f => document.fonts.add(f)).catch(() =>
      toast(`${i.name} is not a font this browser can read`, true));
  }
}

// --- colour -------------------------------------------------------------------
//
// The maths mirrors tests/unit/test_palette_vision.gd exactly: same linearisation,
// same luminance coefficients, same Viénot matrices. The desk is here to tell you
// before `make test` does, never to disagree with it.

const toLinear = v => v <= 0.04045 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4);
const toSrgb = v => v <= 0.0031308 ? v * 12.92 : 1.055 * Math.pow(v, 1 / 2.4) - 0.055;
const luma = c => 0.2126 * toLinear(c[0]) + 0.7152 * toLinear(c[1]) + 0.0722 * toLinear(c[2]);
const contrast = (a, b) => (Math.max(luma(a), luma(b)) + 0.05) / (Math.min(luma(a), luma(b)) + 0.05);
const distance = (a, b) => Math.hypot(a[0] - b[0], a[1] - b[1], a[2] - b[2]);

const MATRIX = {
  protan: [[0.11238, 0.88762, 0], [0.11238, 0.88762, 0], [0.00401, -0.00401, 1]],
  deuter: [[0.29275, 0.70725, 0], [0.29275, 0.70725, 0], [-0.02234, 0.02234, 1]],
  tritan: [[1, 0.14461, -0.14461], [0, 0.86124, 0.13876], [0, 0.86124, 0.13876]],
};

function simulate(c, mode) {
  const m = MATRIX[mode];
  if (!m) return c;
  const l = [toLinear(c[0]), toLinear(c[1]), toLinear(c[2])];
  return m.map(row => toSrgb(Math.min(1, Math.max(0,
    row[0] * l[0] + row[1] * l[1] + row[2] * l[2]))));
}

const hex = c => '#' + c.slice(0, 3)
  .map(v => Math.round(Math.min(1, Math.max(0, v)) * 255).toString(16).padStart(2, '0')).join('');
const fromHex = h => [1, 3, 5].map(i => parseInt(h.substr(i, 2), 16) / 255);

function drawColour() {
  const c = COLOUR;
  $('colour-brief').innerHTML = esc(c.note)
    + ` The tokens are read from <code>src/view/palette.gd</code> and the values written`
    + ` straight back into the <code>.tres</code> — so an edit here is a commit, not a preview.`
    + ` Run <code>make test</code> after: this page checks the same floors, but only the test`
    + ` is the gate.`
    + (c.rules.unreadable.length
      ? `<br><b style="color:var(--warn)">Could not read ${esc(c.rules.unreadable.join(', '))}
         out of the test — the checks below are incomplete.</b>` : '');

  $('palbar').innerHTML = c.palettes.map(p => `
    <button data-pal="${esc(p.name)}" class="${p.name === PALETTE ? 'on' : ''}">
      ${esc(p.name)}<span class="meta"> · ${esc(c.rules.modes[p.name] || 'grey')}</span>
    </button>`).join('');
  $('palbar').querySelectorAll('button').forEach(b => b.addEventListener('click', () => {
    PALETTE = b.dataset.pal; drawColour();
  }));

  const pal = c.palettes.find(p => p.name === PALETTE);
  if (!pal) return;
  const mode = c.rules.modes[PALETTE] || 'grey';
  const value = t => pal.values[t] || [1, 0, 1, 1];

  // Every check the test runs, in the test's own order.
  const rows = [];
  for (const [a, b] of c.rules.apart) {
    const sa = simulate(value(a), mode), sb = simulate(value(b), mode);
    const dl = Math.abs(luma(sa) - luma(sb)), dd = distance(sa, sb);
    rows.push({
      what: `${a} / ${b}`, pair: [value(a), value(b)],
      ok: dl >= c.rules.floors.MIN_LUMA || dd >= c.rules.floors.MIN_DISTANCE,
      shown: `Δluma ${dl.toFixed(3)}`,
      want: `apart under ${mode} — needs Δluma ${c.rules.floors.MIN_LUMA} or Δrgb ${c.rules.floors.MIN_DISTANCE} (Δrgb ${dd.toFixed(3)})`,
    });
  }
  for (const [a, b] of c.rules.greyscale) {
    const ratio = contrast(value(a), value(b));
    rows.push({
      what: `${a} / ${b}`, pair: [value(a), value(b)],
      ok: ratio >= c.rules.floors.MIN_UI_CONTRAST,
      shown: `${ratio.toFixed(2)}:1`,
      want: `greyscale — WCAG non-text floor ${c.rules.floors.MIN_UI_CONTRAST}:1`,
    });
  }
  for (const t of c.rules.text) {
    const ratio = contrast(value(t), value(c.rules.text_on));
    rows.push({
      what: `${t} on ${c.rules.text_on}`, pair: [value(t), value(c.rules.text_on)],
      ok: ratio >= c.rules.floors.MIN_TEXT_CONTRAST,
      shown: `${ratio.toFixed(2)}:1`,
      want: `§13.7 reading floor ${c.rules.floors.MIN_TEXT_CONTRAST}:1`,
    });
  }

  const bad = rows.filter(r => !r.ok).length;
  $('checks').innerHTML = rows.map(r => `
    <div class="chk ${r.ok ? '' : 'bad'}">
      <span><span class="swatchpair"><i style="background:${hex(r.pair[0])}"></i><i
        style="background:${hex(r.pair[1])}"></i></span>${esc(r.what)}</span>
      <span class="v">${esc(r.shown)}</span>
      <span class="w">${esc(r.want)}</span>
    </div>`).join('')
    + (bad ? '' : '<div class="meta" style="padding:6px 10px">all clear</div>');

  const groups = [];
  for (const t of c.tokens) {
    let g = groups.find(g => g.name === t.group);
    if (!g) groups.push(g = { name: t.group, tokens: [] });
    g.tokens.push(t);
  }
  $('tokens-head').textContent =
    `${c.tokens.length} tokens · editing ${PALETTE}.tres`;
  $('swatches').innerHTML = groups.map(g => `
    <div style="grid-column:1/-1"><h2 style="margin:14px 0 0">${esc(g.name || 'Palette')}</h2></div>
    ` + g.tokens.map(t => {
      const v = value(t.name);
      return `<div class="sw" title="${esc(t.doc)}">
        <input type="color" value="${hex(v)}" data-token="${esc(t.name)}">
        <div class="t"><b>${esc(t.name)}</b><span>${hex(v)}</span></div>
        <div class="a">${v[3] < 1 ? 'α ' + v[3].toFixed(2) : ''}</div>
      </div>`;
    }).join('')).join('');

  $('swatches').querySelectorAll('input[type=color]').forEach(input =>
    input.addEventListener('change', () => saveToken(input.dataset.token, input.value)));
}

async function saveToken(token, value) {
  const pal = COLOUR.palettes.find(p => p.name === PALETTE);
  const alpha = (pal.values[token] || [0, 0, 0, 1])[3];
  const res = await fetch('/api/colour', {
    method: 'POST',
    body: JSON.stringify({ palette: PALETTE, token, rgba: [...fromHex(value), alpha] }),
  });
  const out = await res.json();
  if (!res.ok) return toast(out.error, true);
  toast(`${PALETTE}.tres · ${token} — run make test before you commit it`);
  await loadColour();
}

// --- load ---------------------------------------------------------------------

async function load() {
  DATA = await (await fetch('/api/assets')).json();
  const group = role => DATA.groups.find(g => g.role === role);
  drawArt(DATA.assets);
  drawGlyphs(group('glyphs'));
  drawSfx(group('sfx'));
  drawFonts(group('fonts'));

  const files = DATA.assets.length + DATA.groups.reduce((n, g) => n + g.items.length, 0);
  const here = DATA.assets.filter(a => a.here).length
    + DATA.groups.reduce((n, g) => n + g.found, 0);
  const missing = DATA.assets.filter(a => !a.here).map(a => a.role);
  $('summary').innerHTML =
    `${here} of ${files} files present · ${kb(DATA.bytes)} on disk`
    + (missing.length ? ` · still wanted: <b>${missing.join(', ')}</b>` : '')
    + DATA.groups.filter(g => g.extras.length).map(g =>
        ` · <b>${g.role}: ${g.extras.length} file(s) nothing asked for</b>`).join('');

  drawNav({
    art: `${DATA.assets.filter(a => a.here).length}/${DATA.assets.length}`,
    glyphs: `${group('glyphs').found}/${group('glyphs').want}`,
    sfx: `${group('sfx').found}/${group('sfx').want}`,
    fonts: `${group('fonts').found}/${group('fonts').want}`,
    colour: COLOUR ? `${COLOUR.palettes.length}` : '',
  });
}

async function loadColour() {
  COLOUR = await (await fetch('/api/colour')).json();
  if (!PALETTE || !COLOUR.palettes.some(p => p.name === PALETTE)) {
    PALETTE = (COLOUR.palettes[0] || {}).name;
  }
  drawColour();
}

loadColour().then(load);
</script>
"""


def main():
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 7777
    socketserver.TCPServer.allow_reuse_address = True
    with socketserver.TCPServer(("127.0.0.1", port), Desk) as httpd:
        print("asset desk: http://127.0.0.1:%d   (ctrl-c to stop)" % port)
        print("files land in %s — run `make import` after, then commit them" % ROOT)
        print("colour edits are written straight into src/data/palettes/ — `make test` after")
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("")


if __name__ == "__main__":
    main()
