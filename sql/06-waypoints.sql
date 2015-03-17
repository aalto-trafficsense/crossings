-- Waypoints are the final result spatial points

DROP TABLE IF EXISTS waypoints;

CREATE TABLE waypoints (
  id        bigint PRIMARY KEY,
  geo       geography(point, 4326) NOT NULL,
  osm_nodes bigint[] NOT NULL
);

INSERT INTO waypoints
  SELECT
    (round(ST_X(cluster.center) * 10000)) * 1000000 +
    (round(ST_Y(cluster.center) * 10000)),
    cluster.center,
    cluster.nodes AS nodes
  FROM (
    SELECT
      ST_Transform(ST_Centroid(geometry), 4326) AS center,
      nodes
    FROM clusters
    WHERE ready IS TRUE
  ) AS cluster
;

CREATE INDEX ON waypoints USING GIN(osm_nodes);
CREATE INDEX ON waypoints USING GIST(geo);
