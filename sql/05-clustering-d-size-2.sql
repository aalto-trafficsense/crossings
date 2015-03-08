-- Regions with two clusters will always have their two clusters combined into a single one.
-- Otherwise they would not be in the same region in the first place!

DO $$
DECLARE
  current_region integer;
  count integer;
BEGIN
  count := 0;
  FOR current_region IN (SELECT region_id FROM clusters GROUP BY region_id HAVING COUNT(id) = 2) LOOP
    INSERT INTO clusters (nodes, geometry, region_id, ready)
      SELECT
        a.nodes || b.nodes AS nodes,
        ST_Collect(a.geometry, b.geometry) AS geometry,
        current_region AS region_id,
        true AS ready
      FROM clusters AS a
      JOIN clusters AS b
      ON a.id < b.id
      WHERE a.region_id = current_region AND b.region_id = current_region;

    DELETE FROM clusters
    WHERE region_id = current_region
    AND ready IS FALSE;

    count := count + 1;
  END LOOP;

  RAISE NOTICE 'size=2 regions processed: %', count;
END $$;
