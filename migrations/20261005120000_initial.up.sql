CREATE TABLE users (
  id BIGSERIAL PRIMARY KEY,
  username TEXT NOT NULL UNIQUE,
  email TEXT NOT NULL UNIQUE,
  password_hash TEXT NOT NULL,
  bio TEXT,
  image TEXT
);

CREATE TABLE follows (
  follower_id BIGINT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  followee_id BIGINT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  PRIMARY KEY (follower_id, followee_id)
);

-- Tags live on the article as an ordered array, because the API returns them in the order the
-- author gave them.
CREATE TABLE articles (
  id BIGSERIAL PRIMARY KEY,
  slug TEXT NOT NULL UNIQUE,
  title TEXT NOT NULL,
  description TEXT NOT NULL,
  body TEXT NOT NULL,
  tag_list TEXT[] NOT NULL DEFAULT '{}',
  author_id BIGINT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp()
);

CREATE INDEX articles_recent ON articles (created_at DESC, id DESC);
CREATE INDEX articles_author ON articles (author_id);
CREATE INDEX articles_tags ON articles USING GIN (tag_list);

CREATE TABLE favorites (
  user_id BIGINT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  article_id BIGINT NOT NULL REFERENCES articles (id) ON DELETE CASCADE,
  PRIMARY KEY (user_id, article_id)
);

CREATE INDEX favorites_article ON favorites (article_id);

CREATE TABLE comments (
  id BIGSERIAL PRIMARY KEY,
  body TEXT NOT NULL,
  article_id BIGINT NOT NULL REFERENCES articles (id) ON DELETE CASCADE,
  author_id BIGINT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp()
);

CREATE INDEX comments_article ON comments (article_id, created_at DESC);

-- Everything about an article that does not depend on who is asking.
CREATE VIEW article_details AS
  SELECT a.id, a.slug, a.title, a.description, a.body, a.tag_list, a.created_at, a.updated_at,
         a.author_id, u.username AS author_username, u.bio AS author_bio, u.image AS author_image,
         (SELECT count(*) FROM favorites f WHERE f.article_id = a.id) AS favorites_count
    FROM articles a JOIN users u ON u.id = a.author_id;

-- The API's timestamp format: ISO 8601 in UTC with milliseconds.
CREATE FUNCTION iso_time(t TIMESTAMPTZ) RETURNS TEXT
  LANGUAGE sql IMMUTABLE
  RETURN to_char(t AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"');
