-- The roads_nodes table contains all nodes of roads

DROP TABLE IF EXISTS roads_nodes;

-- TODO: This table could be TEMPORARY
CREATE UNLOGGED TABLE roads_nodes (
  road_id     bigint NOT NULL,
  node_id     bigint NOT NULL,
  is_endpoint boolean NOT NULL
);

INSERT INTO roads_nodes
  SELECT
    road_id,
    node_id,
    (node_index = 1 OR node_index = nodes.count)
  FROM (
    SELECT DISTINCT osm_id FROM roads
  ) roads
  JOIN (
    SELECT id AS road_id, node_id, node_index, array_length(nodes, 1) AS count
    FROM planet_osm_ways, unnest(nodes)
    WITH ORDINALITY x(node_id, node_index)
  ) AS nodes
  ON osm_id = nodes.road_id
;

CREATE INDEX ON roads_nodes (node_id, road_id, is_endpoint);
