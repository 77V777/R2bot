require('dotenv').config();
const express = require('express');
const { S3Client, PutObjectCommand, ListObjectsV2Command, GetObjectCommand } = require('@aws-sdk/client-s3');
const { getSignedUrl } = require('@aws-sdk/s3-request-presigner');
const crypto = require('crypto');

const app = express();
app.use(express.json());

const R2_ACCOUNT_ID = process.env.R2_ACCOUNT_ID;
const R2_ACCESS_KEY_ID = process.env.R2_ACCESS_KEY_ID;
const R2_SECRET_ACCESS_KEY = process.env.R2_SECRET_ACCESS_KEY;
const R2_BUCKET = process.env.R2_BUCKET;
// 打印已加载的环境变量（掩码敏感值）并在缺失时退出，便于调试
console.log('Loaded env: R2_ACCOUNT_ID=', R2_ACCOUNT_ID ? (R2_ACCOUNT_ID.slice(0,6) + '...') : 'MISSING', 'R2_BUCKET=', R2_BUCKET ? R2_BUCKET : 'MISSING');
if (!R2_ACCOUNT_ID || !R2_ACCESS_KEY_ID || !R2_SECRET_ACCESS_KEY || !R2_BUCKET) {
  console.error('Please set R2_ACCOUNT_ID, R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY, R2_BUCKET in .env');
  process.exit(1);
}

const endpoint = `https://${R2_ACCOUNT_ID}.r2.cloudflarestorage.com`;

const s3 = new S3Client({
  region: 'auto',
  endpoint,
  credentials: {
    accessKeyId: R2_ACCESS_KEY_ID || '',
    secretAccessKey: R2_SECRET_ACCESS_KEY || '',
  },
  forcePathStyle: false,
});

function randomKey(ext = 'jpg') {
  return `${Date.now()}-${crypto.randomBytes(6).toString('hex')}.${ext}`;
}

app.get('/', (req, res) => res.send('R2 Presign Server is running'));

app.post('/get-presigned-url', async (req, res) => {
  try {
    const { contentType = 'image/jpeg', ext = 'jpg' } = req.body || {};
    const key = randomKey(ext);

    const command = new PutObjectCommand({
      Bucket: R2_BUCKET,
      Key: key,
      ContentType: contentType,
    });

    const signedUrl = await getSignedUrl(s3, command, { expiresIn: 600 });

    res.json({ url: signedUrl, key });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'failed to create presigned url', details: String(err) });
  }
});

// 列出 bucket 中最近的对象（方便确认上传结果）
app.get('/list-objects', async (req, res) => {
  try {
    const maxKeys = parseInt(req.query.max || '20', 10);
    const listCmd = new ListObjectsV2Command({ Bucket: R2_BUCKET, MaxKeys: maxKeys });
    const out = await s3.send(listCmd);
    // 返回简单的对象数组
    const items = (out.Contents || []).map(o => ({ Key: o.Key, Size: o.Size, LastModified: o.LastModified }));
    res.json({ objects: items });
  } catch (err) {
    console.error('list error', err);
    res.status(500).json({ error: 'failed to list objects', details: String(err) });
  }
});

// 生成 presigned GET URL，客户端可用它直接下载预览对象
app.get('/get-presigned-get', async (req, res) => {
  try {
    const key = req.query.key;
    if (!key) return res.status(400).json({ error: 'missing key' });

    // 支持可选 expires 参数（秒），默认为 86400（1 天），最大允许 7 天（604800 秒）
    let expires = parseInt(req.query.expires || '', 10);
    if (isNaN(expires) || expires <= 0) expires = 86400;
    const MAX_EXPIRES = 7 * 24 * 3600; // 7 days
    if (expires > MAX_EXPIRES) expires = MAX_EXPIRES;

    const getCmd = new GetObjectCommand({ Bucket: R2_BUCKET, Key: key });
    const signedUrl = await getSignedUrl(s3, getCmd, { expiresIn: expires });
    res.json({ url: signedUrl, expires });
  } catch (err) {
    console.error('get-presign-get error', err);
    res.status(500).json({ error: 'failed to create presigned get url', details: String(err) });
  }
});

const port = process.env.PORT || 3000;
app.listen(port, () => console.log(`Presign server listening on ${port}`));
