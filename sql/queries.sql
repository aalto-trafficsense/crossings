DROP TABLE IF EXISTS roads;

CREATE TABLE roads AS
  SELECT DISTINCT
    osm_id as road_id, name, oneway, way as geom
  FROM
    planet_osm_line
  WHERE
    highway NOT IN ('cycleway', 'footway', 'pedestrian', 'steps', 'service', 'path', 'platform', 'construction')
;
