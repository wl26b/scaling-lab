DROP TABLE IF EXISTS likes, posts, users CASCADE;

CREATE TABLE users (
  id         serial PRIMARY KEY,
  username   text NOT NULL UNIQUE,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE posts (
  id         bigserial PRIMARY KEY,
  user_id    int NOT NULL REFERENCES users(id),
  body       text NOT NULL,
  like_count int NOT NULL DEFAULT 0,   -- denormalized so the feed never has to count likes
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE likes (
  user_id    int    NOT NULL REFERENCES users(id),
  post_id    bigint NOT NULL REFERENCES posts(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, post_id)       -- one like per user per post
);
