-- 50k users, 500k posts, ~2M likes, generated inside Postgres (no data files to ship).
SET synchronous_commit = off;

INSERT INTO users (username, created_at)
SELECT 'user' || g, now() - random() * interval '365 days'
FROM generate_series(1, 50000) g;

-- Inserted oldest-first so id order == time order (the feed sorts by id).
INSERT INTO posts (user_id, body, created_at)
SELECT (1 + floor(random() * 50000))::int,
       'Post #' || g || ': ' || md5(random()::text) || ' ' || md5(random()::text),
       ts
FROM (
  SELECT g, now() - random() * interval '90 days' AS ts
  FROM generate_series(1, 500000) g
  ORDER BY ts
) s;

-- Random (user, post) pairs; the primary key drops the rare duplicate.
INSERT INTO likes (user_id, post_id)
SELECT (1 + floor(random() * 50000))::int, (1 + floor(random() * 500000))::bigint
FROM generate_series(1, 2000100)
ON CONFLICT DO NOTHING;

UPDATE posts p SET like_count = c.n
FROM (SELECT post_id, count(*) AS n FROM likes GROUP BY post_id) c
WHERE p.id = c.post_id;

-- Indexes added after the bulk load (much faster than maintaining them row by row).
CREATE INDEX likes_post_id_idx ON likes (post_id);
CREATE INDEX posts_user_id_idx ON posts (user_id);

VACUUM ANALYZE;
