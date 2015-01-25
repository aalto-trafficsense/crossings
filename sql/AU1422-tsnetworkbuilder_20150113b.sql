
/*
﻿ 	Queries to Produce trafficSense Experimental Tables from Imported OSM Data.

	 --------------------------------------
	 -- WARNING:  A L P H A  VERSION  ----------
	 --------------------------------------


	      *****          ***
	     *** ***         ***
	    ***   ***        ***
	   ***********       ***
	  *************      ***
	 ***         ***     
	***           ***    ***

	(c) 2015 Aalto University
	v: 2015.01.13b ALPHA
	
	Contact mtziotis@mail.ntua.gr for any more info, suggestions, etc.

	All work is experimental.
	Expect changes without any notice.
	The structure & logic focus on development.
	No optimization of resources' use.
	Many bugs & errors. Many of them already known.
	

*/


/*	BASIC REQUIREMENTS.
	 --------------------------------------

		This Script has been tested with
			PostreSQL 9.4
			PostGIS 2.1.5
		on Ubuntu Linux 14.04 LTS 64bits

		Other Extensions needed:
			hstore
			intarray

		OSM-data must be imported by osm2pgsql
		and 'highwaymodes' table must be created or restored.		

		Please note that intarray must be loaded AFTER the import of the OSM data, as latest versions of osm2pgsql face problems.
*/



/*	EXTRA NOTES
	--------------------------------------

	The links between the waypoints are created with a very simple procedure. This is faster than the full one, and doesn't require extra libraries.
	The whole code will be replaced when the specifications of the links are fully set.

*/



/* CreateRoadsList */

/*	This query selects from the planet_osm_line table the following columns:
		osm_id as road_id,
		way as geom (the string used by postgis to store the geometrical information)

	and adds boolean fields about the modes permitted.

	The term 'roads' is used for any 'way'.

	The modes are contained in the highwaymodes table.

	Specific modes and road types can be excluded either by modifying the 'highwaymodes' table, or the WHERE clause.

	E.G. use

		WHERE
			planet_osm_line.highway=highwaymodes.highway AND highwaymodes.motorcar=true AND planet_osm_line.highway<>'service'

	to include only motorcars and exclude service roads.	

	


*/


DROP TABLE IF EXISTS roadslist;

CREATE TABLE roadslist AS




	SELECT DISTINCT ON (osm_id)
		osm_id as road_id, highwaymodes.motorcar, highwaymodes.bicycle,highwaymodes.foot, highwaymodes.rail, way as geom
	FROM
		planet_osm_line,
		highwaymodes
	WHERE
/*		planet_osm_line.highway=highwaymodes.highway      <- NORMAL CLAUSE WITHOUT ANY EXCLUSIONS */
		planet_osm_line.highway=highwaymodes.highway AND highwaymodes.motorcar=true AND planet_osm_line.highway<>'service'

;


ALTER TABLE roadslist ADD PRIMARY KEY (road_id);
ALTER TABLE roadslist ALTER COLUMN motorcar SET NOT NULL;
ALTER TABLE roadslist ALTER COLUMN bicycle SET NOT NULL;
ALTER TABLE roadslist ALTER COLUMN foot SET NOT NULL;
ALTER TABLE roadslist ALTER COLUMN rail SET NOT NULL;



/* Append trains and trams
---------------------------

	Information about Trams and Trains is contained in the same table but in the 'railway' and not the 'highway' field. 
*/

INSERT INTO roadslist	
	SELECT DISTINCT ON (osm_id)
		osm_id as road_id, false, false,false, true, way as geom
	FROM
		planet_osm_line
	WHERE
		planet_osm_line.railway='rail' OR planet_osm_line.railway='tram' OR planet_osm_line.railway='subway'
;
	

/* CreateRoadsNodesInOrder */

/*	The planet_osm_ways table contains information about any way of the OSM data.
	There is a field with the id of each way, and a field with an array that contains an ordered list with the ids of the nodes which are the vertices of this way.

	The query unfolds the array for the ways which are roads, creating one row for each element. This row contains information about

		the road_id,
		the order of the node in the sequence (rn),
		the node id.

	For example, the row: 4216933, {25031706,25199769,1703484739,25031731} is unfolded as:

		road_id	rn	node_id
		-----------------------
		4216933, 1, 2503706
		4216933, 2, 25199769
		4216933, 3, 1703484739
		4216933, 4, 25031731
	
*/

/* Improve Performance */

CREATE INDEX "idx-roadslist-geom"
  ON roadslist
  USING gist
  (geom);



DROP TABLE IF EXISTS roadsnodesinorder;

CREATE TEMPORARY TABLE roadsnodesinorder AS

SELECT roadslist.road_id, node_num AS rn, node_id, (node_num = 1 OR node_num = nodes.count) AS is_endpoint
FROM roadslist
JOIN
	(
		SELECT id AS road_id, node_id, node_num, array_length(nodes, 1) AS count
		FROM
			planet_osm_ways,
			unnest(nodes)
		WITH ORDINALITY x(node_id, node_num)
	) AS nodes
ON roadslist.road_id = nodes.road_id;

ALTER TABLE roadsnodesinorder ALTER COLUMN road_id SET NOT NULL;
ALTER TABLE roadsnodesinorder ALTER COLUMN node_id SET NOT NULL;
ALTER TABLE roadsnodesinorder ALTER COLUMN rn SET NOT NULL;
ALTER TABLE roadsnodesinorder ALTER COLUMN is_endpoint SET NOT NULL;

CREATE INDEX ON roadsnodesinorder (road_id);
CREATE INDEX ON roadsnodesinorder (node_id);



/* CreateRoadsNodesData */

/* 	This query creates the roadsnodesdata table with the geometrical data of the nodes that are elements of the road network.
	Each row contains information about

		the node_id
		the point geometry that represents the node.

	The geometrical information is included in other tables too, even if there might be joins to the current table. The reason is that the visualization of a table requires the geometrical information being existed in one of its fields and not in a joined field of another table. This means that a query cannot be visualized directly.
*/
	



DROP TABLE IF EXISTS roadsnodesdata;

CREATE TABLE roadsnodesdata AS

	SELECT 
		roadsnodeslist.node_id, ST_SetSRID(ST_MakePoint((lon::double precision)/100,(lat::double precision)/100),900913) as geom

	FROM
		planet_osm_nodes,

		(
			SELECT DISTINCT
				node_id
			FROM
				roadsnodesinorder
		) AS roadsnodeslist

		WHERE
			planet_osm_nodes.id=roadsnodeslist.node_id
;
		

ALTER TABLE roadsnodesdata ALTER COLUMN node_id SET NOT NULL;
ALTER TABLE roadsnodesdata ALTER COLUMN geom SET NOT NULL;


/* Improve Performance */

CREATE UNIQUE INDEX "idx-roadsnodesdata-node_id"
  ON roadsnodesdata
  USING btree
  (node_id);












/* Create Points of Importance */

/* 	This query finds the nodes which are Points of Importance (POImps).
	POImps are e.g. intersections of 2 roads, dead ends (in relation to the modes), bus stops, etc. 
*/


DROP TABLE IF EXISTS poimplist;

CREATE TEMPORARY TABLE poimplist AS

WITH nodes AS (
	/* Find nodes in more than 2 roads.
		These nodes are intersections in any case.
	*/
	SELECT node_id
	FROM roadsnodesinorder
	GROUP BY node_id
	HAVING COUNT(road_id) > 2

	UNION

	/* Find nodes that are geometrical dead ends.
		These nodes are POImps independently of the mode.
	*/
	SELECT node_id
	FROM roadsnodesinorder
	GROUP BY node_id
	/* bool_or is needed, because we are interested in nodes that are endpoints in *at least one* road */
	HAVING COUNT(road_id) = 1 AND bool_or(is_endpoint) IS TRUE

	UNION

	/* Find nodes that are part of 2 roads, and not the first or the last one of both of them.
		These nodes are simple intersections.
	*/
	SELECT node_id
	FROM roadsnodesinorder
	GROUP BY node_id
	/* bool_or is needed, because we are interested in nodes that are not endpoints in *both* roads */
	HAVING COUNT(road_id) = 2 AND bool_and(is_endpoint) IS FALSE
)

SELECT distinct_nodes.node_id, roadsnodesdata.geom
FROM
	(SELECT DISTINCT node_id FROM nodes) AS distinct_nodes
JOIN
	roadsnodesdata
ON roadsnodesdata.node_id = distinct_nodes.node_id
;

ALTER TABLE poimplist ADD PRIMARY KEY (node_id);
ALTER TABLE poimplist ALTER COLUMN geom SET NOT NULL;



/* Find nodes that are part of 2 roads, first and/or last items of both roads, and mode related deadends.
*/

/* Joonas: This query is faulty, because the last WHERE expression is never true, because nofroads=nofmotorcar=nofbicycle=noffoot=nofrail (see subquery for the reason) */
INSERT INTO poimplist
	SELECT DISTINCT roadsnodesdata.node_id, roadsnodesdata.geom
	FROM
		/* Joonas: This subquery is faulty, because COUNT(expression) returns the number of non-null rows. The columns motorcar, bicycle, foot, rail are false or true, so the counts will always be same as nofroads. */
		(
			SELECT roadsnodesinorder.node_id,COUNT(roadslist.road_id) as nofroads, COUNT(roadslist.motorcar) as nofmotorcar,COUNT(roadslist.bicycle) as nofbicycle,COUNT(roadslist.foot) as noffoot,COUNT(roadslist.rail) as nofrail
			FROM	
				roadslist,
				roadsnodesinorder
			WHERE
				roadsnodesinorder.road_id=roadslist.road_id
			GROUP BY
				roadsnodesinorder.node_id
		) as foo,
		(
				SELECT road_id, max(rn) as nofrn FROM roadsnodesinorder GROUP BY road_id
		) as foo2,
		roadsnodesdata,
		roadsnodesinorder
	WHERE
		foo.node_id=roadsnodesdata.node_id AND
		foo.node_id=roadsnodesinorder.node_id AND
		nofroads=2 AND
		roadsnodesinorder.road_id=foo2.road_id AND
		(roadsnodesinorder.rn=1 OR roadsnodesinorder.rn=foo2.nofrn) AND
		(foo.nofmotorcar<foo.nofroads OR foo.nofbicycle<foo.nofroads OR foo.noffoot<foo.nofroads OR foo.nofrail<foo.nofroads)
;


/* Append Bus Stops
	Append items from the 'planet_osm_point' table with the 'bus_stop' value in the highway field.
*/ 

INSERT INTO poimplist
	SELECT
		planet_osm_point.osm_id as node_id, planet_osm_point.way as geom
	FROM
		planet_osm_point
	WHERE
		planet_osm_point.highway='bus_stop'
;




/* Spatial Index to Improve the Performance */

CREATE INDEX "idx-poimplist-geom"
  ON poimplist
  USING gist
  (geom);







/* The following Function does the clustering of the POImps.
--------------------------------------------------------------
*/

CREATE OR REPLACE FUNCTION buc(radius integer)
RETURNS TABLE (cluster_id int, geom geometry) AS
$BODY$

DECLARE
srid int;
clusterstobejoined int[];
threshold int;
newmaxdistance int;
regionid int;
nofregions int;

BEGIN
threshold :=2*radius;


/* Create a temporary table with the POImps
	Assign a clusterid to each point.
*/

DROP TABLE IF EXISTS tmppoimp2;
CREATE TEMPORARY TABLE tmppoimp2 (gid bigint, the_geom geometry(Point), the_clusterid serial);
INSERT INTO tmppoimp2(gid, the_geom)
    (SELECT poimplist.node_id, poimplist.geom FROM poimplist); 

/* The indexes are useful in case there are many items in a region.
	The efficiency is limited if only a few items are existent.
*/

/* Improve Performance */

CREATE INDEX "idx-tmppoimp2-geom"
  ON tmppoimp2
  USING gist
  (the_geom);


ALTER TABLE tmppoimp2 ADD COLUMN region_id integer;

/*	At first, the fuction has a top-down step, in which regions are formed.
	Each region includes POImps that all of them are isolated from other regions (distance > radius) but can form clusters.
	Thus, calculations are performed for items of the same region only.
*/

DROP TABLE IF EXISTS poimpregions;

CREATE TEMPORARY TABLE poimpregions AS
	SELECT ST_Dump(ST_UNION(ST_Buffer(tmppoimp2.the_geom,radius))) as dump
	FROM tmppoimp2
;

ALTER TABLE poimpregions ADD COLUMN region_id integer;
ALTER TABLE poimpregions ADD COLUMN geom geometry(Polygon);

UPDATE poimpregions
SET
	region_id=(dump).path[1],
	geom=(dump).geom
;	

ALTER TABLE poimpregions DROP COLUMN dump;

nofregions := (SELECT max(poimpregions.region_id) FROM poimpregions);

RAISE NOTICE 'No of Regions= %', nofregions;


/* Assign a region id to each POImp
*/

UPDATE tmppoimp2
SET region_id=
	poimpregions.region_id
FROM
	poimpregions
WHERE ST_Within(tmppoimp2.the_geom,poimpregions.geom)=true
;



/* Improve Performance */

CREATE INDEX "idx-tmppoimp2-clusterid"
  ON tmppoimp2
  USING btree
  (the_clusterid);

CREATE INDEX "idx-tmppoimp2-region_id"
  ON tmppoimp2
  USING btree
  (region_id);

ANALYZE tmppoimp2;


/* The following table contains information about the pairs of clusters.
*/

DROP TABLE IF EXISTS tmppoimp2clusterspairs;

CREATE TEMPORARY TABLE tmppoimp2clusterspairs AS


   SELECT a.region_id, a.the_clusterid as cluster_id1,b.the_clusterid as cluster_id2, ST_Distance(a.the_geom,b.the_geom) as dist
        FROM tmppoimp2 a, tmppoimp2 b
        WHERE a.the_clusterid < b.the_clusterid AND
        a.region_id=b.region_id
;

/* Improve Performance */

CREATE INDEX "idx-tmppoimp2clusterspairs-clusterid1"
  ON tmppoimp2clusterspairs
  USING btree
  (cluster_id1);

CREATE INDEX "idx-tmppoimp2clusterspairs-clusterid2"
  ON tmppoimp2clusterspairs
  USING btree
  (cluster_id2);

CREATE INDEX "idx-tmppoimp2clusterspairs-dist"
  ON tmppoimp2clusterspairs
  USING btree
  (dist);

CREATE INDEX "idx-tmppoimp2clusterspairs-region_id"
  ON tmppoimp2clusterspairs
  USING btree
  (region_id);


/* The following table contains the information about each cluster.
*/

DROP TABLE IF EXISTS tmppoimp2clusters;
CREATE TEMPORARY TABLE tmppoimp2clusters AS
   SELECT tmppoimp2.the_clusterid, ST_Collect(tmppoimp2.the_geom) as the_geom
        FROM tmppoimp2
	GROUP BY the_clusterid
;


/* Improve Performance */

CREATE UNIQUE INDEX "idx-tmppoimp2clusters-clusterid"
  ON tmppoimp2clusters
  USING btree
  (the_clusterid);


regionid := 0;

/* The first loop regards the regions.
*/


LOOP

regionid := regionid+1;

	/* The second loop regards the clusters in the current region.
	*/ 

	LOOP

		clusterstobejoined :=
			ARRAY [tmppoimp2clusterspairs.cluster_id1, tmppoimp2clusterspairs.cluster_id2, floor(tmppoimp2clusterspairs.dist),tmppoimp2clusterspairs.region_id]
		FROM
			tmppoimp2clusterspairs
		WHERE tmppoimp2clusterspairs.region_id=regionid
		ORDER BY dist ASC
		LIMIT 1
		;
		
RAISE NOTICE 'Region= % / %', regionid, nofregions;


		/* Exit Condition.
		The value is Null in case only one item forms the cluster.
		*/
		
		IF clusterstobejoined[3]>threshold OR clusterstobejoined[3] Is Null
		THEN
			EXIT;
		END IF;



		/* Update the clusters.
		*/

		UPDATE tmppoimp2clusters
			SET the_geom=
				ST_Collect(tmppoimp2clusters.the_geom, b.the_geom)
			FROM
				tmppoimp2clusters b
			WHERE
				tmppoimp2clusters.the_clusterid=clusterstobejoined[1] AND b.the_clusterid=clusterstobejoined[2]
		;



		UPDATE tmppoimp2
			SET the_clusterid = clusterstobejoined[1]
			WHERE the_clusterid = clusterstobejoined[2]
		;


		/* Delete pairs that are not existent any more.
		*/
		
		DELETE FROM tmppoimp2clusterspairs
			WHERE cluster_id1=clusterstobejoined[2] OR cluster_id2=clusterstobejoined[2]
		;

		DELETE FROM tmppoimp2clusters
			WHERE the_clusterid=clusterstobejoined[2]
		;




		/* Calculate new distances between the clusters.
		*/

		UPDATE tmppoimp2clusterspairs
			SET dist =
		(SELECT ST_MaxDistance(a.the_geom,b.the_geom)
		

			FROM
				tmppoimp2clusters a,
				tmppoimp2clusters b
			WHERE a.the_clusterid=cluster_id1 AND b.the_clusterid=cluster_id2
		)
		WHERE
			(cluster_id1=clusterstobejoined[1] OR cluster_id2=clusterstobejoined[1])
			AND tmppoimp2clusterspairs.region_id=regionid

		;



		--If there's only 1 cluster left, exit loop
		IF
			(SELECT COUNT(*) FROM tmppoimp2clusterspairs) < 2
		THEN
			EXIT;
		END IF;

		
	END LOOP;


	/* Check if this is the fibal region.
	*/
	
	IF
		regionid=nofregions
	THEN
		EXIT;
	END IF;
	
END LOOP;

RETURN QUERY SELECT the_clusterid,the_geom FROM tmppoimp2;
END;
$BODY$
LANGUAGE plpgsql
;


/* This query calls the clustering Function.
*/

DROP TABLE IF EXISTS tmppoimpsclustered;

CREATE TEMPORARY TABLE tmppoimpsclustered AS


SELECT (clusters).* FROM 
		(
			SELECT buc(30) AS clusters
		) foo
;



/* The result of the clustering Function is POIimps with information about their cluster.
	This query finds the centroid of each cluster and creates a set of waypoints.
*/

DROP TABLE IF EXISTS tmpwaypoints;

CREATE TEMPORARY TABLE tmpwaypoints AS

	SELECT DISTINCT
		cluster_id, ST_Centroid(mycollection) AS geom
	FROM
		(
			SELECT
				cluster_id, ST_Collect(geom) AS mycollection
			FROM
				tmppoimpsclustered
			GROUP BY
				cluster_id
			) AS foo
;



/* This query adds a disk of radius=30 as a buffer in each waypoint, (just for the visualization at this moment, but also for the creation of a mask later).
*/

ALTER TABLE tmpwaypoints ADD COLUMN wpt_buffer geometry("POLYGON",900913);

UPDATE tmpwaypoints
SET wpt_buffer=
ST_Buffer(geom,30)
;

/* Improve Performance */

CREATE INDEX "idx-tmpwaypoints-wpt_buffer"
  ON tmpwaypoints
  USING gist
  (wpt_buffer);





/* Create the Final 'WAYPOINTS' Table
-----------------------------------------
*/


DROP TABLE IF EXISTS waypoints;

CREATE TABLE waypoints (wpt_id bigint, geom geometry(Point,4326));
INSERT INTO waypoints
(SELECT 0, ST_Transform(geom,4326)
FROM tmpwaypoints)
;


UPDATE waypoints
SET wpt_id=
(SELECT round(ST_X(geom)*10000)*1000000+round(ST_Y(geom)*10000))
;

ALTER TABLE waypoints ADD PRIMARY KEY (wpt_id);


/* A temporary table for a not so smart way to change ids in the 'links' table to WGS84 formatted ones. (At the end.)
*/

DROP TABLE IF EXISTS tmpwaypointsoldnewids;

CREATE TEMPORARY TABLE tmpwaypointsoldnewids (wpt_id bigint, geom geometry(Point,4326), internalid integer);
INSERT INTO tmpwaypointsoldnewids
(SELECT 0, ST_Transform(geom,4326), cluster_id
FROM tmpwaypoints)
;

UPDATE tmpwaypointsoldnewids
SET wpt_id=
(SELECT round(ST_X(geom)*10000)*1000000+round(ST_Y(geom)*10000))
;

ALTER TABLE tmpwaypointsoldnewids DROP COLUMN geom;



































/* ----------------------------------------------------------------------------------------------
	THE SECTION BELOW HAS BEEN REPLACED.
	BUT THIS ONE IS A FAST SOLUTION TO CREATE & VISUALIZE THE LINKS BETWEEN THE WAYPOINTS.
	(Its Descriptions are very short.)


	THE REPLACEMENT REQUIRES EXTRA LIBRARIES, RELATED TO SFCGAL.
-------------------------------------------------------------------------------------------------
*/






/*	Create a Line for each Road
*/	

DROP TABLE IF EXISTS tmproadslist2;
CREATE TEMPORARY TABLE tmproadslist2 AS


	SELECT ST_MakeLine(ARRAY(SELECT roadsnodesdata.geom 
					FROM 
					roadsnodesdata,
					roadsnodesinorder a
					WHERE 
					a.node_id = roadsnodesdata.node_id AND a.road_id=roadsnodesinorder.road_id
					ORDER BY a.rn)
					) as geom
	FROM roadsnodesinorder
	GROUP BY roadsnodesinorder.road_id
;




/* Improve Performance */

CREATE INDEX "idx-tmproadslist2-geom"
  ON tmproadslist2
  USING gist
  (geom);



/* Create a mask from the buffers of the waypoints
*/

DROP TABLE IF EXISTS tmpcollectionofwaypointsbuffer;
CREATE TEMPORARY TABLE tmpcollectionofwaypointsbuffer AS
	SELECT ST_Union(wpt_buffer) as geom
	FROM tmpwaypoints
;


/* Improve Performance */

CREATE INDEX "idx-tmpcollectionofwaypointsbuffer-geom"
  ON tmpcollectionofwaypointsbuffer
  USING gist
  (geom);



/* Remove the segments of the road lines that are within the waypoints' mask
	and dump the elements.
*/

DROP TABLE IF EXISTS tmproadslist3;
CREATE TEMPORARY TABLE tmproadslist3 AS

	SELECT (ST_Dump(ST_Difference(tmproadslist2.geom,tmpcollectionofwaypointsbuffer.geom))).geom as geom
	 FROM tmpcollectionofwaypointsbuffer, tmproadslist2
	;










/* Insert Short Paths between Overlapping Waypoints */ 

INSERT INTO tmproadslist3 (geom)
	SELECT ST_MakeLine(t1.geom,t2.geom)
	FROM tmpwaypoints t1,
	tmpwaypoints t2
	WHERE t1.cluster_id<t2.cluster_id AND ST_Distance(t1.geom,t2.geom)<=60
;

/* Improve Performance */

CREATE INDEX "idx-tmproadslist3-geom"
  ON tmproadslist3
  USING gist
  (geom);





/* Create a collection of the waypoints to be used to connect the Paths With the Waypoints (below)
*/

DROP TABLE IF EXISTS tmpcollectionofwaypoints;
CREATE TEMPORARY TABLE tmpcollectionofwaypoints AS
	SELECT ST_Collect(geom) as geom
	FROM tmpwaypoints
;


/* Improve Performance */

CREATE INDEX "idx-tmpcollectionofwaypoints-geom"
  ON tmpcollectionofwaypoints
  USING gist
  (geom);



/* Connect the Paths With the Waypoints
	This is a very fast way, but theoretically not always reliable. 
*/

UPDATE tmproadslist3
SET geom=ST_Snap(tmproadslist3.geom, tmpcollectionofwaypoints.geom, 30.01)
FROM tmpcollectionofwaypoints
;



/* Redump the collected roads.
*/

DROP TABLE IF EXISTS tmproadslist4;
CREATE TEMPORARY TABLE tmproadslist4 AS

	SELECT (ST_Dump(ST_LineMerge(ST_Collect(tmproadslist3.geom)))).geom as geom
	 FROM tmproadslist3
	;

/* Simplify the Lines to improve performance
*/

UPDATE tmproadslist4
	SET geom=ST_SimplifyPreserveTopology(geom,5)
;



/* Improve Performance */

CREATE INDEX "idx-tmproadslist4-geom"
  ON tmproadslist4
  USING gist
  (geom);


/* HERE IS THE PLACE FOR THE CODE ABOUT THE CREATION OF ADDITIONAL POImps IN CASE OF PARTIALLY PARALLEL PATHS. 
----------------------------------------------------------------------------------------------------------------------

TODO!

*/






/* Here starts the clustering procedure for the paths.
--------------------------------------------------------
*/



/* Create path ids.
*/

ALTER TABLE tmproadslist4 ADD COLUMN path_id serial;

ALTER TABLE tmproadslist4 ADD COLUMN cluster1 int;
ALTER TABLE tmproadslist4 ADD COLUMN cluster2 int;


/* Assign the start/end waypoints to the paths.
*/

UPDATE tmproadslist4
SET cluster1=
(SELECT tmpwaypoints.cluster_id
FROM tmpwaypoints
WHERE ST_Distance(tmpwaypoints.wpt_buffer,ST_LineInterpolatePoint(tmproadslist4.geom,0))<0.01
LIMIT 1)
;

UPDATE tmproadslist4
SET cluster2=
(SELECT tmpwaypoints.cluster_id
FROM tmpwaypoints
WHERE ST_Distance(tmpwaypoints.wpt_buffer,ST_LineInterpolatePoint(tmproadslist4.geom,1))<0.01
LIMIT 1)
;



/* Set cluster1 < cluster2 */

UPDATE tmproadslist4
SET cluster1=t2.cluster2, cluster2=t2.cluster1
FROM tmproadslist4 as t2
WHERE tmproadslist4.path_id=t2.path_id AND tmproadslist4.cluster1>tmproadslist4.cluster2
;




/* Create a table with the paths that are similars.
	Similars are those paths that their geometries are contained in the 2*radius buffers of each other.
*/

DROP TABLE IF EXISTS tmpsimilarpaths; 

CREATE TEMPORARY TABLE tmpsimilarpaths AS
SELECT t1.cluster1,t1.cluster2,t1.path_id as pathid1,t2.path_id as pathid2, ST_Contains(ST_Buffer(t1.geom,60),t2.geom) as isSimilar
FROM tmproadslist4 t1, tmproadslist4 t2
WHERE
t1.cluster1=t2.cluster1 AND t1.cluster2=t2.cluster2 AND t1.path_id<=t2.path_id 
;


/* Create a table to be used for the lists of clusters and their members.
*/

DROP TABLE IF EXISTS tmpfillclusters; 

CREATE TEMPORARY TABLE tmpfillclusters AS
SELECT DISTINCT cluster1,cluster2, pathid1 as cluster1st
FROM tmpsimilarpaths
;


ALTER TABLE tmpfillclusters ADD COLUMN clustermembers integer[];

UPDATE tmpfillclusters SET clustermembers[1]=cluster1st;


/* Fill the lists.
*/

UPDATE tmpfillclusters SET clustermembers=
clustermembers||ARRAY(SELECT tmpsimilarpaths.pathid2
FROM tmpsimilarpaths
WHERE tmpsimilarpaths.isSimilar=true AND tmpsimilarpaths.pathid1=cluster1st AND tmpsimilarpaths.pathid2<>cluster1st)
;

UPDATE tmpfillclusters SET clustermembers=
clustermembers||ARRAY(SELECT tmpsimilarpaths.pathid1
FROM tmpsimilarpaths
WHERE tmpsimilarpaths.isSimilar=true AND tmpsimilarpaths.pathid2=cluster1st AND tmpsimilarpaths.pathid1<>cluster1st)
;


/* Create a table with the clusters and its members.
*/

DROP TABLE IF EXISTS tmpclusters;

CREATE TEMPORARY TABLE tmpclusters AS
	SELECT DISTINCT cluster1,cluster2, sort(clustermembers) as clustermembers
	FROM tmpfillclusters
;



ALTER TABLE tmpclusters DROP COLUMN IF EXISTS cluster_id;
ALTER TABLE tmpclusters ADD COLUMN cluster_id serial;

DELETE FROM tmpclusters
USING (SELECT cluster_id,clustermembers FROM tmpclusters) as foo
WHERE tmpclusters.clustermembers <@ foo.clustermembers AND foo.cluster_id<>tmpclusters.cluster_id;







/* Create a link to represent each cluster of paths.
 	In this fast and simple solution, the link created is identical to the shortest of the members.
*/

DROP TABLE IF EXISTS tmpclusteredpaths;
CREATE TEMPORARY TABLE tmpclusteredpaths AS


	WITH minlengthofcluster AS
	(
		(
		WITH lengthsofmembers AS
			(
			WITH listofmembers AS
				(
				SELECT tmpclusters.cluster_id, unnest(clustermembers) as path_id
				FROM tmpclusters)
			SELECT tmpclusters.cluster_id,ST_Length(tmproadslist4.geom) as pathlength
			FROM tmpclusters,tmproadslist4,listofmembers
			WHERE 
				tmpclusters.cluster_id=listofmembers.cluster_id AND
				tmproadslist4.path_id=listofmembers.path_id
			)

		SELECT cluster_id,min(pathlength) as clustersminlength
		FROM lengthsofmembers
		GROUP BY cluster_id
		)
	)

	SELECT DISTINCT ON (cluster_id)
	       tmpclusters.cluster_id,   tmpclusters.cluster1, tmpclusters.cluster2, pathslist.path_id,tmproadslist4.geom
	FROM  tmpclusters,minlengthofcluster,tmproadslist4,(
						SELECT tmpclusters.cluster_id, unnest(clustermembers) as path_id
						FROM tmpclusters
						) AS pathslist

	WHERE tmpclusters.cluster_id=minlengthofcluster.cluster_id AND tmpclusters.cluster_id=pathslist.cluster_id AND pathslist.path_id=tmproadslist4.path_id AND minlengthofcluster.clustersminlength=ST_Length(tmproadslist4.geom)
	ORDER BY cluster_id, tmproadslist4.path_id ASC
;


/* Try to further simplify the links
----------------------------------

DROP TABLE IF EXISTS tmpclusteredpathssimplified;
CREATE TABLE tmpclusteredpathssimplified AS
	SELECT ST_SimplifyPreserveTopology(geom,5)
	FROM  tmpclusteredpaths
;
*/



DROP TABLE IF EXISTS links;

CREATE TABLE links
	(
	lnk_id character(26),
	lnk_1 bigint,
	lnk_2 bigint,
	lnk_index smallint,
	lnk_directionality text,
	lnk_geom geometry("LINESTRING",4326),
	lnk_mode1 text,
	lnk_mode2 text
	)
;

INSERT INTO links(lnk_id,lnk_1,lnk_2,lnk_index,lnk_directionality,lnk_geom,lnk_mode1,lnk_mode2)

SELECT cluster_id , cluster1 as lnk_1, cluster2 as lnk_2, row_number() OVER (PARTITION BY cluster_id ORDER BY ST_length(ST_Transform(geom,4326)) ASC) as lnk_index, NULL as lnk_directionality,  ST_Transform(geom,4326) as link_geom, null, null

FROM tmpclusteredpaths
;



/* Update lnk IDS with WGS84 formatted IDS.
------------------------------------------
*/

UPDATE links
SET
	lnk_1=
		tmpwaypointsoldnewids.wpt_id
FROM
	tmpwaypointsoldnewids
WHERE
	tmpwaypointsoldnewids.internalid=links.lnk_1
;

UPDATE links
SET
	lnk_2=
		tmpwaypointsoldnewids.wpt_id
FROM
	tmpwaypointsoldnewids
WHERE
	tmpwaypointsoldnewids.internalid=links.lnk_2
;

/* Exchange lnk_1 & lnk_2 in case lnk_1>lnk_2
	(Strange, but it works!)
*/

UPDATE links
	SET lnk_1 = lnk_2, lnk_2 = lnk_1
WHERE lnk_2<lnk_1
;


/* Form 24 from 26 lnk_id
*/
UPDATE links
	SET lnk_id=
		(lnk_1)::text || (lnk_2)::text
;	

/* Add lnk_index as suffix
*/
UPDATE links
	SET lnk_id=
		lnk_id || lpad(lnk_index::text,2,'0')
;


/* FURTHER IMPROVEMENTS AT THIS POINT AFTER SETTING FULL SPECIFICATIONS ABOUT THE 'links' TABLE. */

/* -----  D O N E  ----- */







