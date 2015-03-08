-- Regions divide the clustering into subproblems

DROP TABLE IF EXISTS regions CASCADE;

CREATE UNLOGGED TABLE regions (
  id       serial PRIMARY KEY,
  geometry geometry(Polygon, 3857) NOT NULL
);

INSERT INTO regions (geometry)
  SELECT (ST_Dump(ST_Union(ST_Buffer(geometry, 30)))).geom
  FROM poimps
;

CREATE INDEX ON regions USING GIST(geometry);
