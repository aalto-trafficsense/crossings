# Notes about design choices

## Unlogged tables

All the temporary tables are marked as unlogged, so they are not crash-safe. If there is a crash during the processing, we can always start again, and using unlogged tables gives a performance boost to write operations.

## Geometry projections

Geometries in the OSM data use the EPSG:900913 projection, which is equivalent to EPSG:3857. 900913 is not an official projection, so for example QGis doesn't recognize it automatically. This is why we "transform" all the geometries to the official EPSG:3857 projection when reading data from the OSM tables. In practice this probably does nothing to the actual values, but simply changes the SRID.

So, all temporary tables use EPSG:3857. In the final tables we use EPSG:4326 (WGS84 longitude/latitude).

# Notes about the clustering algorithm

The clustering algorithm is based on hierarchical clustering using the single-linkage criteria. Points of importance are grouped into regions, which are the separate and individual subproblems in the algorithm. Processing of each region is divided into several phases depending on the size of a region:

## size=1

If a region has only a single cluster, it is ready without any additional processing. In practice the majority of all regions are like this, so it's a very important optimization.

## size=2

If a region has only two clusters, we must always combine the clusters into one. If the two clusters would be too far apart for the joining, they would be separate regions.

## size=N

Only regions with more than 2 clusters are eligible for the hierarchical clustering.
