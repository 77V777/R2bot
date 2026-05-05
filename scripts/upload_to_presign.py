import os
import sys
import json
import requests

PRESIGN_SERVER = os.environ.get('PRESIGN_SERVER', 'http://localhost:3000')

def upload_file(path):
    basename = os.path.basename(path)
    mime = 'application/zip'
    ext = path.split('.')[-1]
    print(f'Requesting presign for {basename}...')
    r = requests.post(f'{PRESIGN_SERVER}/get-presigned-url', json={'contentType': mime, 'ext': ext})
    if r.status_code != 200:
        print('Presign failed:', r.status_code, r.text)
        return False
    body = r.json()
    url = body['url']
    key = body.get('key', basename)
    print('Uploading to presigned URL...')
    with open(path, 'rb') as f:
        rr = requests.put(url, data=f, headers={'content-type': mime})
    if rr.status_code in (200,201):
        print('Upload success:', key)
        return True
    else:
        print('Upload failed:', rr.status_code, rr.text)
        return False

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print('Usage: upload_to_presign.py <path-to-file>')
        sys.exit(2)
    path = sys.argv[1]
    if not os.path.exists(path):
        print('File not found:', path)
        sys.exit(2)
    ok = upload_file(path)
    sys.exit(0 if ok else 1)
