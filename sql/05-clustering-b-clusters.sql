DROP TABLE IF EXISTS clusters CASCADE;

CREATE UNLOGGED TABLE clusters (
  id        serial PRIMARY KEY,
  nodes     bigint[] NOT NULL, -- we keep track of OSM node ids for each cluster
  geometry  geometry(Geometry, 3857) NOT NULL,
  region_id integer NOT NULL,
  ready     boolean NOT NULL DEFAULT false
);

-- At first each poimp has its own cluster
INSERT INTO clusters (nodes, geometry, region_id)
  SELECT array[node_id], poimps.geometry, regions.id
  FROM poimps 
  JOIN regions
  ON ST_Within(poimps.geometry, regions.geometry)
;

CREATE INDEX ON clusters USING GIST(geometry);
CREATE INDEX ON clusters (region_id, id);
CREATE INDEX ON clusters (ready);

-- Print some statistics about clusters
DO $$
DECLARE
  stats record;
BEGIN
  SELECT
    COUNT(nullif(regions.size = 1, false)) AS size_1_count,
    COUNT(nullif(regions.size = 2, false)) AS size_2_count,
    COUNT(nullif(regions.size > 2, false)) AS size_N_count,
    COUNT(*) AS total_count,
    max(regions.size) AS max_size
  INTO stats
  FROM (
    SELECT COUNT(region_id) AS size
    FROM clusters
    GROUP BY region_id
  ) AS regions;

  RAISE NOTICE 'size=1 regions: %', stats.size_1_count;
  RAISE NOTICE 'size=2 regions: %', stats.size_2_count;
  RAISE NOTICE 'size=N regions: %', stats.size_N_count;
  RAISE NOTICE 'total  regions: %', stats.total_count;
  RAISE NOTICE 'maximum region size: %', stats.max_size;

END $$;
