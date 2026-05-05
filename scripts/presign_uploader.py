#!/usr/bin/env python3
"""
presign_uploader.py

批量并行上传工具，使用后端 presign 接口：
 - POST /get-presigned-url  -> 获取 PUT presign URL and key
 - PUT presigned URL 上传文件
 - 可选：调用 GET /get-presigned-get?key=...&expires=... 获取 presigned GET 下载链接

用法示例：
  python presign_uploader.py C:\path\to\file1.jpg C:\path\to\file2.zip --concurrency 4
  python presign_uploader.py --dir ./to_upload --concurrency 8 --get-download-links --expires 3600

输出：在当前目录生成 `upload_results.csv`（local_path,key,download_url）
"""
import argparse
import concurrent.futures
import csv
import mimetypes
import os
import sys
import time
from functools import partial

try:
    import requests
except Exception:
    print('This script requires `requests`. Install with `pip install requests`')
    raise


def request_presign(presign_server, path, session, ext=None, content_type=None):
    if content_type is None:
        content_type = mimetypes.guess_type(path)[0] or 'application/octet-stream'
    if ext is None:
        ext = os.path.splitext(path)[1].lstrip('.') or 'dat'
    url = presign_server.rstrip('/') + '/get-presigned-url'
    try:
        r = session.post(url, json={'contentType': content_type, 'ext': ext}, timeout=15)
        r.raise_for_status()
        data = r.json()
        return data['url'], data.get('key')
    except Exception as e:
        raise RuntimeError(f'presign request failed for {path}: {e}')


def upload_to_presigned(put_url, path, session, chunk_size=64 * 1024, on_progress=None):
    total = os.path.getsize(path)
    sent = 0
    with open(path, 'rb') as f:
        headers = {'content-type': mimetypes.guess_type(path)[0] or 'application/octet-stream'}
        # stream with requests
        def gen():
            nonlocal sent
            while True:
                chunk = f.read(chunk_size)
                if not chunk:
                    break
                sent += len(chunk)
                if on_progress:
                    on_progress(sent, total)
                yield chunk

        r = session.put(put_url, data=gen(), headers=headers, timeout=120)
        if r.status_code not in (200, 201):
            raise RuntimeError(f'upload failed status={r.status_code} body={r.text}')
        return True


def worker_upload(path, presign_server, get_download_link, expires, retries, session, idx=None):
    last_err = None
    for attempt in range(1, retries + 1):
        try:
            put_url, key = request_presign(presign_server, path, session)

            def on_progress(sent, total):
                pct = sent / total * 100
                if idx is not None:
                    print(f'[#{idx}] {os.path.basename(path)} {pct:.0f}%')
                else:
                    print(f'{os.path.basename(path)} {pct:.0f}%')

            upload_to_presigned(put_url, path, session, on_progress=on_progress)

            download_url = None
            if get_download_link and key:
                # request presigned GET
                try:
                    q = {'key': key, 'expires': expires}
                    r = session.get(presign_server.rstrip('/') + '/get-presigned-get', params=q, timeout=15)
                    r.raise_for_status()
                    data = r.json()
                    download_url = data.get('url')
                except Exception:
                    download_url = None

            return {'path': path, 'key': key, 'download_url': download_url}
        except Exception as e:
            last_err = e
            wait = 2 ** (attempt - 1)
            print(f'Error uploading {path} attempt {attempt}/{retries}: {e}. Retrying in {wait}s')
            time.sleep(wait)

    raise RuntimeError(f'Failed to upload {path} after {retries} attempts; last error: {last_err}')


def gather_files(args):
    files = []
    if args.dir:
        for root, _, filenames in os.walk(args.dir):
            for fn in filenames:
                files.append(os.path.join(root, fn))
    files.extend(args.files or [])
    # filter
    files = [f for f in files if os.path.isfile(f)]
    return files


def main():
    p = argparse.ArgumentParser(description='Batch uploader using presign server')
    p.add_argument('files', nargs='*', help='Files to upload')
    p.add_argument('--dir', help='Directory to upload (recursively)')
    p.add_argument('--presign-server', default='http://localhost:3000', help='Presign server base URL')
    p.add_argument('--concurrency', type=int, default=4, help='Parallel upload workers')
    p.add_argument('--retries', type=int, default=3, help='Upload retries per file')
    p.add_argument('--get-download-links', action='store_true', help='Request presigned GET download links after upload')
    p.add_argument('--expires', type=int, default=3600, help='Download link expiry seconds (if --get-download-links); max allowed by server')
    p.add_argument('--output', default='upload_results.csv', help='CSV output file mapping local_path,key,download_url')
    args = p.parse_args()

    files = gather_files(args)
    if not files:
        print('No files found to upload')
        sys.exit(2)

    session = requests.Session()
    results = []

    with concurrent.futures.ThreadPoolExecutor(max_workers=args.concurrency) as ex:
        futures = {}
        for i, path in enumerate(files, start=1):
            fut = ex.submit(worker_upload, path, args.presign_server, args.get_download_links, args.expires, args.retries, session, i)
            futures[fut] = path

        for fut in concurrent.futures.as_completed(futures):
            path = futures[fut]
            try:
                res = fut.result()
                print(f'Uploaded: {path} -> {res.get("key")}')
                results.append(res)
            except Exception as e:
                print(f'Failed: {path}: {e}')

    # write CSV
    with open(args.output, 'w', newline='', encoding='utf-8') as csvf:
        w = csv.writer(csvf)
        w.writerow(['local_path', 'key', 'download_url'])
        for r in results:
            w.writerow([r.get('path'), r.get('key'), r.get('download_url')])

    print(f'Done. Results saved to {args.output}')


if __name__ == '__main__':
    main()
