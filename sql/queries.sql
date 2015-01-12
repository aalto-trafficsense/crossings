DROP TABLE IF EXISTS roads;

CREATE TABLE roads AS
  SELECT
  DISTINCT ON (osm_id)
    osm_id as id,
    name,
    CASE WHEN oneway = 'yes' THEN true ELSE false END AS oneway,
    way as geom
  FROM
    planet_osm_line
  WHERE
    highway NOT IN ('cycleway', 'footway', 'pedestrian', 'steps', 'service', 'path', 'platform', 'construction')
;

ALTER TABLE roads ADD PRIMARY KEY (id);
ALTER TABLE roads ALTER COLUMN geom SET NOT NULL;
ALTER TABLE roads ALTER COLUMN oneway SET NOT NULL;
