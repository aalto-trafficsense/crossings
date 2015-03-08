-- size=N clusters are processed one region at a time with this hierarchical clustering algorithm
-- The linkage criteria used here is single-linkage clustering (join by shortest distance)

DO $$
DECLARE
  current_region integer;
  new_cluster integer;
  pair record;
  count integer;
BEGIN
  count := 0;
  FOR current_region IN (SELECT region_id FROM clusters GROUP BY region_id HAVING COUNT(id) > 2) LOOP
    -- This loop is the actual algorithm for a single region
    LOOP
      -- Select and consume the pair with the least distance (single-linkage clustering)
      DELETE FROM cluster_pairs
      WHERE id IN (
        SELECT id
        FROM cluster_pairs
        WHERE region_id = current_region
        AND distance <= 60
        ORDER BY distance ASC
        LIMIT 1
      )
      RETURNING id, cluster_a, cluster_b INTO pair;

      -- Exit condition: no more pairs within small enough distance
      IF pair.id IS NULL THEN EXIT; END IF;

      -- Combine the pair into a single cluster
      INSERT INTO clusters (nodes, geometry, region_id)
        SELECT
          a.nodes || b.nodes AS nodes,
          ST_Collect(a.geometry, b.geometry) AS geometry,
          current_region AS region_id
        FROM
          clusters AS a,
          clusters AS b
        WHERE a.id = pair.cluster_a AND b.id = pair.cluster_b
      RETURNING id INTO new_cluster;

      -- Since both source clusters are now invalid, delete all pairs that involve them
      DELETE FROM cluster_pairs
      WHERE
        cluster_a IN (pair.cluster_a, pair.cluster_b) OR
        cluster_b IN (pair.cluster_a, pair.cluster_b);

      -- Delete both source clusters
      DELETE FROM clusters
      WHERE id IN (pair.cluster_a, pair.cluster_b);

      -- Calculate and insert all possible pairs involving the new cluster
      INSERT INTO cluster_pairs (region_id, cluster_a, cluster_b, distance)
        SELECT
          a.region_id,
          a.id,
          b.id,
          ST_MaxDistance(a.geometry, b.geometry)
        FROM clusters AS a
        JOIN clusters AS b
        ON b.id < a.id AND a.region_id = b.region_id
        WHERE a.id = new_cluster AND b.ready IS FALSE
        AND ST_DWithin(a.geometry, b.geometry, 60)
      ;
    END LOOP;

    UPDATE clusters
    SET ready = true
    WHERE region_id = current_region;

    count := count + 1;
  END LOOP;

  RAISE NOTICE 'size=N regions processed: %', count;
END $$;
