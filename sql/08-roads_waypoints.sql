-- Waypoints that are reachable from roads
-- The tuple (W, R) for waypoint W and road R is in the table if any of the
-- following statements are true:

-- 1. Waypoint is an intersection in road R
-- 2. Waypoint is an endpoint in road R
-- 3. Statement 1 or 2 is true for any road R^ where R^ is reachable by following the
--    graph in roads_joins table

DROP TABLE IF EXISTS roads_waypoints;

CREATE TABLE roads_waypoints (
  road_id     bigint NOT NULL,
  waypoint_id bigint NOT NULL
);

-- All nodes involved in the clustering end up in waypoints,
-- so we can simply fetch the corresponding roads by using the roads_nodes table
INSERT INTO roads_waypoints
  SELECT
    road_id,
    waypoints.id
  FROM roads_nodes
  JOIN waypoints
  ON waypoints.osm_nodes @> array[node_id]
;

-- We recursively traverse the graph represented by roads_joins, and find out
-- all roads connections and waypoints
INSERT INTO roads_waypoints
  WITH RECURSIVE recurse_roads(road_a, road_b) AS (
      SELECT l.road_a, r.road_b
      FROM roads_joins AS l
      JOIN roads_joins AS r
      ON l.road_a = r.road_a
    UNION
      SELECT l.road_a, r.road_b
      FROM recurse_roads AS l
      JOIN roads_joins AS r
      ON l.road_b = r.road_a
  )
  SELECT DISTINCT road_a, waypoints.id AS waypoint
  FROM recurse_roads
  JOIN roads_nodes
  ON road_id = road_b
  JOIN waypoints
  ON waypoints.osm_nodes @> array[node_id]
  WHERE road_a != road_b
;

CREATE INDEX ON roads_waypoints (road_id);
