DROP TABLE IF EXISTS cluster_pairs;

CREATE TEMPORARY TABLE cluster_pairs (
  id        serial PRIMARY KEY,
  region_id integer NOT NULL,
  cluster_a integer NOT NULL,
  cluster_b integer NOT NULL,
  distance  float NOT NULL
);

INSERT INTO cluster_pairs (region_id, cluster_a, cluster_b, distance)
  SELECT
    a.region_id,
    a.id,
    b.id,
    ST_MaxDistance(a.geometry, b.geometry)
  FROM clusters AS a
  JOIN clusters AS b
  -- a.id < b.id guarantees that for any clusters A and B
  -- we only get one of the pairs (A, B) and (B, A)
  ON a.id < b.id AND a.region_id = b.region_id
  WHERE a.ready IS FALSE AND b.ready IS FALSE
  AND ST_DWithin(a.geometry, b.geometry, 60)
;

CREATE INDEX ON cluster_pairs (region_id, distance, id);
CREATE INDEX ON cluster_pairs (cluster_a);
CREATE INDEX ON cluster_pairs (cluster_b);
