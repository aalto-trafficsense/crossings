/*	All Queries needed to Produce trafficSense experimental tables from imported OSM data.

	(c) 2014.09 Aalto University
	v: 2014.09.20a
	Contact michail.tziotis@aalto.fi for any more info, suggestions, etc.
*/




/* CreateRoadsList */

/*	This query selects from the planet_osm_line table the following columns:
		osm_id as road_id,
		name,
		oneway (yes, no, null)
		way as geom (the string used by postgis to store the geometrical information)

	Lines are selected as roads if the highway field contains a value and this is not one of the following:
		cycleway,
		footway,
		pedestrian,
		steps,
		service,
		path,
		platform,
		construction

*/

DROP TABLE IF EXISTS roadslist;

CREATE TABLE roadslist AS
SELECT osm_id as road_id, name, oneway, way as geom
FROM planet_osm_line
WHERE (highway NOT  LIKE 'cycleway') AND (highway NOT LIKE 'footway') AND (highway NOT LIKE 'pedestrian') AND (highway NOT LIKE 'steps') AND (highway NOT  LIKE 'service') AND (highway NOT LIKE 'path') AND (highway NOT LIKE 'platform') AND (highway NOT LIKE 'construction');



/* CreateRoadsNodesInOrder */

/*	The planet_osm_ways table contains information about any way of the OSM data.
	A way is any item with a linear geometry.
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

DROP TABLE IF EXISTS roadsnodesinorder;

CREATE TABLE
	roadsnodesinorder
AS

	SELECT
		id as road_id, rn, nodes[rn] AS node_id
	FROM
		(
			SELECT
				id, nodes, generate_subscripts(planet_osm_ways.nodes, 1) AS rn
			FROM
				planet_osm_ways
		) as nodesofways,
		
		roadslist

	WHERE
		roadslist.road_id=nodesofways.id
;





/* CreateRoadsNodesData */

/* 	This query creates the roadsnodesdata table with the geometrical data of the nodes that are elements of the road network.
	Each row contains information about

		the node_id
		the point geometry that represents the node.

	The geometrical information is included in other tables too, even if there might be joins to the current table. 
	The reason is that the visualization of a table requires the geometrical information being existed in one of its fields and not in a joined field of another table.
	This means that a query cannot be visualized directly, and only its resultant table can be visualized.
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
		



/* CreateRoadsNodesWithDifferentNamesList */

/* 	This query finds the nodes which are elements of at least 2 roads with different names, and thus, they are crossings.
	The ... COUNT(DISTINCT ... function counts the different names of the roads which are related to each node. The CASE statement is used to cope with the NULL values.
	The geometry information is included in the resultant table just for its easy visualization.
*/


DROP TABLE IF EXISTS roadsnodeswithdifferentnameslist;

CREATE TABLE roadsnodeswithdifferentnameslist AS

	SELECT foo.node_id, roadsnodesdata.geom
	FROM
		(
			SELECT 
				node_id, COUNT(DISTINCT (CASE WHEN name IS NOT NULL THEN name ELSE '' END)) AS noroadswithdifferentnames
			FROM 
				public.roadsnodesinorder, 
				public.roadslist
			WHERE 
				roadsnodesinorder.road_id = roadslist.road_id
			GROUP BY node_id
		) AS foo,
		roadsnodesdata
	WHERE
	noroadswithdifferentnames>1 AND
	roadsnodesdata.node_id=foo.node_id
		
;




/* CreateRoadsIntersections */

/* 	This query creates a table with a point in each row; the generalized intersection of crossings in a distance less than 55 m from each other, which form a spatial cluster.
	The resultant table contains a field with the id of the intersection, a concatenated string of its 900913 coordinates, and a field with the point geometry.
	The DISTINCT statement is needed because there is one collection for each node of the intersection. All these collections are identical, and they have the same centroid.   
	ST_X and ST_Y functions return the X and Y coordinates of the centroid, to be used as the id.
	The '::text' is used for the the conversion of the big integers to the corresponding strings.
*/

DROP TABLE IF EXISTS roadsintersections;

CREATE TABLE roadsintersections AS

	SELECT DISTINCT
		(ST_X(ST_Centroid(mycollection)) ::bigint)::text || (ST_Y(ST_Centroid(mycollection)) ::bigint)::text AS intersection_id,ST_Centroid(mycollection) AS geom
	FROM
		(
			SELECT
				t1.node_id,ST_Collect(t2.geom) AS mycollection
			FROM
				roadsnodeswithdifferentnameslist AS t1,
				roadsnodeswithdifferentnameslist AS t2
			WHERE
				ST_DWithin(t1.geom, t2.geom, 55)=true
			GROUP BY
			t1.node_id
			) AS foo
;




/* CreateRoadsIntersectionsNodes */

/* 
	This query is similar to the previous one. It creates a table that contains the ids of the nodes which are related to an intersection, and the id of this intersection for each node.
*/


DROP TABLE IF EXISTS roadsintersectionsnodes;

CREATE TABLE roadsintersectionsnodes AS

	SELECT DISTINCT
		node_id,(ST_X(ST_Centroid(mycollection)) ::bigint)::text || (ST_Y(ST_Centroid(mycollection))::bigint)::text AS intersection_id
	FROM
		(
			SELECT
				t1.node_id,ST_Collect(t2.geom) AS mycollection
			FROM
				roadsnodeswithdifferentnameslist AS t1,
				roadsnodeswithdifferentnameslist AS t2
			WHERE
				ST_DWithin(t1.geom, t2.geom, 55)=true
			GROUP BY
				t1.node_id
		) AS foo
;



/* CreateRoadsNodesDeadEnds */

/* 	This query creates a table with the deadends as points.
	A node is recognized as a deadend if:
		it is related to just one road
		and
		it is the first or the last node in the sequence of this road.

	Two subqueries are used.
	The first one, to select the nodes which are related to more than one road.
	The second one, to find the order of the last node in the sequence of each road.
*/   


DROP TABLE IF EXISTS roadsnodesdeadends;

CREATE TABLE roadsnodesdeadends AS

	SELECT
		t1.node_id,geom
	FROM 
		roadsnodesinorder t1,
		roadsnodesdata t2,
	  
		(
			SELECT
				node_id, count(*) AS nodeinhowmanyroadlines
			FROM
				roadsnodesinorder
			GROUP BY
				node_id
		) AS tablewithnodesandnrofroadlines, 


		(
			SELECT road_id, max(rn) AS lastnode
		FROM
			roadsnodesinorder
		GROUP BY
			road_id
		) AS tablewithmaxnodeindex

	WHERE
		t1.node_id=t2.node_id
		AND
		tablewithmaxnodeindex.road_id=t1.road_id
		AND
		tablewithnodesandnrofroadlines.node_id=t1.node_id
		AND
		(t1.rn=lastnode OR t1.rn=1)
		AND 
		nodeinhowmanyroadlines=1
;

