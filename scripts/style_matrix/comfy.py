"""Minimal ComfyUI client. Uses curl on purpose: Cloudflare Access rejects the
header capitalisation urllib produces."""
import json
import os
import subprocess
import time
import uuid

BASE = os.environ.get('COMFYUI_URL', 'https://comfyui.ol1n.com')


def _auth():
    cid = os.environ.get('CF_ACCESS_CLIENT_ID', '')
    sec = os.environ.get('CF_ACCESS_CLIENT_SECRET', '')
    if not cid or not sec:
        raise SystemExit('CF_ACCESS_CLIENT_ID / _SECRET missing (source .env.local)')
    return ['-H', f'CF-Access-Client-Id: {cid}',
            '-H', f'CF-Access-Client-Secret: {sec}']


def _curl(args, binary=False, stdin=None):
    r = subprocess.run(['curl', '-s', '--max-time', '600', *_auth(), *args],
                       input=stdin, capture_output=True)
    if r.returncode:
        raise RuntimeError(f'curl {r.returncode}: {r.stderr[:200]!r}')
    return r.stdout if binary else r.stdout.decode()


def object_info(node):
    return json.loads(_curl([f'{BASE}/object_info/{node}']))


def checkpoints():
    d = object_info('CheckpointLoaderSimple')
    return d['CheckpointLoaderSimple']['input']['required']['ckpt_name'][0]


def submit(workflow):
    body = json.dumps({'prompt': workflow, 'client_id': str(uuid.uuid4())}).encode()
    resp = json.loads(_curl(
        ['-X', 'POST', '-H', 'Content-Type: application/json',
         '--data-binary', '@-', f'{BASE}/prompt'], stdin=body))
    if resp.get('node_errors'):
        raise RuntimeError(f'node_errors: {json.dumps(resp["node_errors"])[:300]}')
    return resp['prompt_id']


def wait(prompt_id, timeout=1800, interval=3):
    deadline = time.time() + timeout
    while time.time() < deadline:
        hist = json.loads(_curl([f'{BASE}/history/{prompt_id}']) or '{}')
        if prompt_id in hist:
            entry = hist[prompt_id]
            status = entry.get('status', {})
            if status.get('status_str') == 'error':
                raise RuntimeError(f'server error: {json.dumps(status)[:300]}')
            if status.get('completed') or entry.get('outputs'):
                return entry
        time.sleep(interval)
    raise TimeoutError(f'{prompt_id} unfinished after {timeout}s')


def images(hist):
    out = []
    for node in hist.get('outputs', {}).values():
        out += [im for im in node.get('images', []) if im.get('type') != 'temp']
    return out


def download(image, path):
    q = (f'filename={image["filename"]}&subfolder={image.get("subfolder", "")}'
         f'&type={image.get("type", "output")}')
    with open(path, 'wb') as fh:
        fh.write(_curl([f'{BASE}/view?{q}'], binary=True))
    return path


def upload(path, name):
    j = json.loads(_curl(['-X', 'POST', '-F', f'image=@{path};filename={name}',
                          '-F', 'overwrite=true', f'{BASE}/upload/image']))
    sub = j.get('subfolder') or ''
    return f'{sub}/{j["name"]}' if sub else j['name']
