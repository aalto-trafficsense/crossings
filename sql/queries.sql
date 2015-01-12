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

DROP TABLE IF EXISTS roads_nodes CASCADE;

CREATE TABLE roads_nodes AS
  SELECT
    roads.id AS road_id,
    node_id,
    idx
  FROM
    roads
  JOIN
    (
      SELECT
        id AS road_id,
        node_id,
        idx
      FROM
        planet_osm_ways,
        unnest(nodes)
      WITH ORDINALITY x(node_id, idx)
    ) AS nodes
  ON
    roads.id = nodes.road_id
;

ALTER TABLE roads_nodes ALTER COLUMN road_id SET NOT NULL;
ALTER TABLE roads_nodes ALTER COLUMN idx SET NOT NULL;
ALTER TABLE roads_nodes ALTER COLUMN node_id SET NOT NULL;
CREATE INDEX ON roads_nodes (road_id);
CREATE INDEX ON roads_nodes (node_id);

DROP TABLE IF EXISTS nodes_crossings;

CREATE TABLE nodes_crossings AS
  SELECT
    id,
    ST_SetSRID(ST_MakePoint((lon::double precision) / 100, (lat::double precision) / 100), 900913) as coord
  FROM
    planet_osm_nodes
  WHERE
    id IN (
      SELECT
        node_id
      FROM
        roads_nodes
      JOIN
        roads
      ON
        roads.id = road_id
      GROUP BY
        node_id
      HAVING
        COUNT(DISTINCT(COALESCE(name, ''))) > 1
    )
;
