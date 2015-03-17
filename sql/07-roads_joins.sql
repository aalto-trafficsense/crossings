-- Pairs of roads that are connected by a common node

DROP TABLE IF EXISTS roads_joins;

CREATE UNLOGGED TABLE roads_joins (
  road_a bigint NOT NULL,
  road_b bigint NOT NULL
);

INSERT INTO roads_joins
  WITH nodes AS (
    SELECT node_id, array_agg(road_id) AS road_ids
    FROM roads_nodes
    GROUP BY node_id
    -- Look for nodes that are endpoints for exactly two roads
    HAVING COUNT(road_id) = 2 AND bool_and(is_endpoint) IS TRUE
  )
  -- *both* pair permutations are included in the resulting table
  SELECT road_ids[1], road_ids[2]
  FROM nodes
  UNION
  SELECT road_ids[2], road_ids[1]
  FROM nodes
;
