import os
import sys
import json
import requests
from pathlib import Path

# 配置：后端地址
SERVER = os.environ.get('R2_PRESIGN_SERVER', 'http://localhost:3000')

# 这里默认使用桌面的 img211.jpg（根据上下文，用户桌面上似乎有该文件）
DESKTOP = os.path.join(os.path.expanduser('~'), 'Desktop')
IMAGE_NAME = 'img211.jpg'
IMAGE_PATH = os.path.join(DESKTOP, IMAGE_NAME)

if not os.path.exists(IMAGE_PATH):
    print(f'找不到示例图片: {IMAGE_PATH}')
    sys.exit(2)

def get_presigned_url(content_type='image/jpeg', ext='jpg'):
    url = SERVER.rstrip('/') + '/get-presigned-url'
    res = requests.post(url, json={'contentType': content_type, 'ext': ext}, timeout=10)
    res.raise_for_status()
    return res.json()


def upload_file(presign_url, file_path, content_type='image/jpeg'):
    with open(file_path, 'rb') as f:
        data = f.read()
    headers = {'Content-Type': content_type}
    res = requests.put(presign_url, data=data, headers=headers, timeout=30)
    return res


if __name__ == '__main__':
    mime = 'image/jpeg'
    ext = Path(IMAGE_PATH).suffix.lstrip('.') or 'jpg'
    print('请求 presigned URL...')
    info = get_presigned_url(content_type=mime, ext=ext)
    presigned = info.get('url')
    key = info.get('key')
    print('收到 presigned URL，上传中...')
    r = upload_file(presigned, IMAGE_PATH, content_type=mime)
    if r.status_code in (200, 201):
        print('上传成功，文件 key =', key)
    else:
        print('上传失败，HTTP', r.status_code)
        print('响应头：', r.headers)
        print('响应体：', r.text)
