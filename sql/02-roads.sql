-- The roads table contains roads that are imported from OSM data

DROP TABLE IF EXISTS roads;

CREATE TABLE roads (
  -- This table doesn't have a primary key, because we don't need any.
  -- osm2pgsql splits long ways to max 100km segments, so osm_id is not unique
  -- Since this table is used for geometry-based queries, using the 100km
  -- segments without joining them is still a good idea.
  osm_id   bigint NOT NULL,
  geo      geography(linestring, 4326) NOT NULL,
  motorcar boolean NOT NULL,
  bicycle  boolean NOT NULL,
  foot     boolean NOT NULL,
  rail     boolean NOT NULL
);

INSERT INTO roads
  WITH roads AS (
    -- Roads based on highwaymodes configuration table
    SELECT
      osm_id,
      way,
      highwaymodes.motorcar, highwaymodes.bicycle,
      highwaymodes.foot, false AS rail
    FROM planet_osm_line
    JOIN highwaymodes USING (highway)
    WHERE highwaymodes.motorcar = true

    UNION ALL

    -- We want some of the unclassified roads as well
    SELECT
      osm_id,
      way,
      true, false,
      false, false
    FROM planet_osm_line
    WHERE highway = 'unclassified' AND name IS NOT NULL

    UNION ALL

    -- Railways
    SELECT
      osm_id,
      way,
      false, false,
      false, true
    FROM planet_osm_line
    WHERE railway IN ('rail', 'subway', 'tram')
  )
  SELECT
    osm_id,
    ST_Transform(way, 4326),
    roads.motorcar, roads.bicycle,
    roads.foot, roads.rail
  FROM roads
;

CREATE INDEX ON roads (osm_id);
CREATE INDEX ON roads USING GIST(geo);
