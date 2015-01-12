DROP TABLE IF EXISTS roads;

CREATE TABLE roads AS
SELECT DISTINCT osm_id as road_id, name, oneway, way as geom
FROM planet_osm_line
WHERE (highway NOT  LIKE 'cycleway') AND (highway NOT LIKE 'footway') AND (highway NOT LIKE 'pedestrian') AND (highway NOT LIKE 'steps') AND (highway NOT  LIKE 'service') AND (highway NOT LIKE 'path') AND (highway NOT LIKE 'platform') AND (highway NOT LIKE 'construction');
