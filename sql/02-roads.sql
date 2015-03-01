-- The roads table contains roads that are imported from OSM data

DROP TABLE IF EXISTS roads;

-- TODO: This table could be TEMPORARY
CREATE UNLOGGED TABLE roads (
  id       bigint PRIMARY KEY,
  geometry geometry(linestring, 3857) NOT NULL,
  motorcar boolean NOT NULL,
  bicycle  boolean NOT NULL,
  foot     boolean NOT NULL,
  rail     boolean NOT NULL
);

INSERT INTO roads
  SELECT DISTINCT ON (osm_id)
    osm_id,
    ST_Transform(way, 3857),
    highwaymodes.motorcar,
    highwaymodes.bicycle,
    highwaymodes.foot,
    false
  FROM planet_osm_line
  JOIN highwaymodes USING (highway)
  WHERE highwaymodes.motorcar = true
;

INSERT INTO roads
  SELECT DISTINCT ON (osm_id)
    osm_id,
    ST_Transform(way, 3857),
    false,
    false,
    false,
    true
  FROM planet_osm_line
  WHERE railway IN ('rail', 'subway', 'tram')
;

CREATE INDEX ON roads USING GIST(geometry);
