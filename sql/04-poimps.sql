-- The poimps table contains points of importance, which are
-- nodes that we are interested in

DROP TABLE IF EXISTS poimps;

CREATE UNLOGGED TABLE poimps (
  node_id  bigint PRIMARY KEY,
  geometry geometry(point, 3857) NOT NULL
);

INSERT INTO poimps
  WITH nodes AS (
    -- Complex intersections
    SELECT node_id
    FROM roads_nodes
    GROUP BY node_id
    HAVING COUNT(road_id) > 2

    UNION ALL

    -- Geometrical dead ends
    SELECT node_id
    FROM roads_nodes
    GROUP BY node_id
    -- bool_or is needed, because we are interested in nodes that are
    -- endpoints in *at least one* road
    HAVING COUNT(road_id) = 1 AND bool_or(is_endpoint) IS TRUE

    UNION ALL

    -- Simple intersections
    SELECT node_id
    FROM roads_nodes
    GROUP BY node_id
    -- bool_or is needed, because we are interested in nodes that are not
    -- endpoints in *both* roads
    HAVING COUNT(road_id) = 2 AND bool_and(is_endpoint) IS FALSE
  )
  SELECT
    nodes.node_id,
    -- 100 is some kind of scaling factor. lon and lat are integers in the planet_osm_nodes table
    ST_SetSRID(ST_MakePoint(lon::double precision / 100, lat::double precision / 100), 3857)
  FROM nodes
  JOIN planet_osm_nodes
  ON id = node_id
;

CREATE INDEX ON poimps USING GIST(geometry);
