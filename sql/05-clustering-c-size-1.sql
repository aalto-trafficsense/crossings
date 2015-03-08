-- Regions with just one cluster are ready without any processing
UPDATE clusters
SET ready = true
WHERE region_id IN (
  SELECT region_id
  FROM clusters
  GROUP BY region_id HAVING COUNT(id) = 1
);
