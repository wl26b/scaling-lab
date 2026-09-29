import cluster from 'node:cluster';
import os from 'node:os';
import Fastify from 'fastify';
import pg from 'pg';

const PORT = Number(process.env.PORT ?? 3000);
// One Node process per vCPU by default. Node runs JS on a single thread, so this is how it uses more than one core.
const WORKERS = Number(process.env.WORKERS ?? os.availableParallelism());
// DB connections per worker. Total = WORKERS * POOL_SIZE; keep it well under Postgres max_connections.
const POOL_SIZE = Number(process.env.POOL_SIZE ?? 10);
const FEED_LIMIT = 20;

if (cluster.isPrimary && WORKERS > 1) {
  console.log(`primary ${process.pid}: starting ${WORKERS} workers`);
  for (let i = 0; i < WORKERS; i++) cluster.fork();
  cluster.on('exit', (worker, code) => {
    console.error(`worker ${worker.process.pid} exited (${code}), restarting`);
    cluster.fork();
  });
} else {
  start();
}

async function start() {
  const pool = new pg.Pool({
    connectionString: process.env.DATABASE_URL ?? 'postgres://app:app@127.0.0.1:5432/social',
    max: POOL_SIZE,
  });

  const app = Fastify({ logger: false });

  // No real auth: the caller says who they are via a header. Fine for a load-test lab only.
  const userId = (req) => {
    const id = Number(req.headers['x-user-id']);
    return Number.isInteger(id) && id > 0 ? id : null;
  };

  app.get('/health', async () => ({ ok: true, pid: process.pid, host: os.hostname() }));

  // Global timeline, newest first. Keyset pagination: pass ?before=<last id you saw>.
  // `liked` = has the caller liked this post (one primary-key lookup per post).
  app.get('/api/feed', async (req) => {
    const before = Number(req.query.before) || null;
    const { rows } = await pool.query(
      `SELECT p.id, p.body, p.like_count, p.created_at, u.id AS user_id, u.username,
              EXISTS (SELECT 1 FROM likes l WHERE l.user_id = $3 AND l.post_id = p.id) AS liked
         FROM posts p JOIN users u ON u.id = p.user_id
        WHERE ($1::bigint IS NULL OR p.id < $1)
        ORDER BY p.id DESC
        LIMIT $2`,
      [before, FEED_LIMIT, userId(req)],
    );
    return { posts: rows, next: rows.length ? rows[rows.length - 1].id : null };
  });

  app.get('/api/posts/:id', async (req, reply) => {
    const { rows } = await pool.query(
      `SELECT p.id, p.body, p.like_count, p.created_at, u.id AS user_id, u.username,
              EXISTS (SELECT 1 FROM likes l WHERE l.post_id = p.id AND l.user_id = $2) AS liked
         FROM posts p JOIN users u ON u.id = p.user_id
        WHERE p.id = $1`,
      [req.params.id, userId(req)],
    );
    if (!rows.length) return reply.code(404).send({ error: 'not found' });
    return rows[0];
  });

  app.post('/api/posts/:id/like', async (req, reply) => {
    const uid = userId(req);
    if (!uid) return reply.code(401).send({ error: 'x-user-id required' });
    // Insert the like and bump the counter in one round trip. Liking twice is a no-op.
    const { rows } = await pool.query(
      `WITH ins AS (
         INSERT INTO likes (user_id, post_id) VALUES ($1, $2)
         ON CONFLICT DO NOTHING RETURNING post_id
       )
       UPDATE posts SET like_count = like_count + 1
        WHERE id IN (SELECT post_id FROM ins)
       RETURNING like_count`,
      [uid, req.params.id],
    );
    return { liked: true, changed: rows.length > 0 };
  });

  app.post('/api/posts', async (req, reply) => {
    const uid = userId(req);
    if (!uid) return reply.code(401).send({ error: 'x-user-id required' });
    const body = typeof req.body?.body === 'string' ? req.body.body.trim().slice(0, 280) : '';
    if (!body) return reply.code(400).send({ error: 'body required' });
    const { rows } = await pool.query(
      `INSERT INTO posts (user_id, body) VALUES ($1, $2) RETURNING id, created_at`,
      [uid, body],
    );
    return reply.code(201).send(rows[0]);
  });

  await app.listen({ port: PORT, host: '127.0.0.1' });
  console.log(`worker ${process.pid} listening on 127.0.0.1:${PORT}`);
}
