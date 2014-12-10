/*	All Queries to Produce trafficSense experimental tables from imported OSM data.

	 --------------------------------------

	 -- WARNING:  ALPHA VERSION  --------------

	 --------------------------------------

	(c) 2014.10 Aalto University
	v: 2014.10.29a
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
  SELECT DISTINCT
    osm_id as road_id, name, (CASE WHEN oneway='yes' THEN true ELSE false END) AS oneway, way as geom
  FROM
    planet_osm_line
  WHERE
    highway NOT IN ('cycleway', 'footway', 'pedestrian', 'steps', 'service', 'path', 'platform', 'construction')
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
		



/* CreateRoadsNodesWithDifferentNamesList */

/* 	This query finds the nodes which are elements of at least 2 roads with different names, and thus, they are crossings.
	The COUNT(DISTINCT function counts the different names of the roads which are related to each node. The CASE statement is used to cope with the NULL values.
	The geometry information is included in the resultant table for its visualization.
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
	The resultant table contains a field with the id of the intersection, a concatenated string of its coordinates, and a field with the point geometry.
	The DISTINCT statement is needed because there is one collection for each node of the intersection. All these collections are identical, and they have the same centroid.   
	The ST_X and ST_Y functions return the X and Y coordinates of the centroid, to be used as the id. The '::text' is used for the the conversion of the big integers of the coordinates to the corresponding strings.
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

/* 	This query is similar to the previous one. It creates a table that contains the ids of the nodes which are related to an intersection, and the id of this intersection for each node.
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
	The first one to select the nodes which are related to more than one road.
	The second one to find the order of the last node in the sequence of each road.
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




DROP TABLE IF EXISTS scsegments;

CREATE TABLE scsegments AS

	SELECT roadslist.road_id,(CASE WHEN oneway like 'yes' THEN true::boolean ELSE false::boolean END) as isOneWay, 1::smallint as direction, ndorigin.rn, ndorigin.node_id as nd1,nddestination.node_id as nd2,1 as length
	

	FROM
		roadsnodesinorder as ndorigin LEFT OUTER JOIN roadsintersectionsnodes as rin1 on ndorigin.node_id=rin1.node_id,
		roadsnodesinorder as nddestination LEFT OUTER JOIN roadsintersectionsnodes as rin2 on nddestination.node_id=rin2.node_id,
		roadslist

	WHERE
		ndorigin.road_id=nddestination.road_id
			AND
		nddestination.rn=ndorigin.rn+1
			AND
		roadslist.road_id=ndorigin.road_id
;





WITH tmpnofnodesinsegment AS

(	SELECT road_id, max(rn) as rn_max
	FROM scsegments
	GROUP BY road_id
)

INSERT INTO scsegments
SELECT scsegments.road_id, false::boolean as isOneWay,2::smallint as direction, rn_max-rn+1, nd2 as nd1, nd1 as nd2, 1 as length

FROM scsegments,
tmpnofnodesinsegment

WHERE scsegments.road_id=tmpnofnodesinsegment.road_id AND scsegments.isOneWay=false
;



ALTER TABLE scsegments ADD COLUMN nd1starde text;
ALTER TABLE scsegments ADD COLUMN nd2starde text;

UPDATE scsegments SET nd1starde=
(SELECT intersection_id
FROM roadsintersectionsnodes
WHERE nd1=node_id)
;

UPDATE scsegments SET nd2starde=
(SELECT intersection_id
FROM roadsintersectionsnodes
WHERE nd2=node_id)
;


UPDATE scsegments SET nd1starde=
(SELECT node_id
FROM roadsnodesdeadends
WHERE scsegments.nd1=roadsnodesdeadends.node_id 
)
WHERE scsegments.nd1starde IS NULL
;

UPDATE scsegments SET nd2starde=
(SELECT node_id
FROM roadsnodesdeadends
WHERE scsegments.nd2=roadsnodesdeadends.node_id
)
WHERE scsegments.nd2starde IS NULL
;





DROP TABLE IF EXISTS scsegments;

CREATE TABLE scsegments AS

	SELECT roadslist.road_id,(CASE WHEN oneway like 'yes' THEN true::boolean ELSE false::boolean END) as isOneWay, 1::smallint as direction, ndorigin.rn, ndorigin.node_id as nd1,nddestination.node_id as nd2,1 as length
	

	FROM
		roadsnodesinorder as ndorigin LEFT OUTER JOIN roadsintersectionsnodes as rin1 on ndorigin.node_id=rin1.node_id,
		roadsnodesinorder as nddestination LEFT OUTER JOIN roadsintersectionsnodes as rin2 on nddestination.node_id=rin2.node_id,
		roadslist

	WHERE
		ndorigin.road_id=nddestination.road_id
			AND
		nddestination.rn=ndorigin.rn+1
			AND
		roadslist.road_id=ndorigin.road_id
;





WITH tmpnofnodesinsegment AS

(	SELECT road_id, max(rn) as rn_max
	FROM scsegments
	GROUP BY road_id
)

INSERT INTO scsegments
SELECT scsegments.road_id, false::boolean as isOneWay,2::smallint as direction, rn_max-rn+1, nd2 as nd1, nd1 as nd2, 1 as length

FROM scsegments,
tmpnofnodesinsegment

WHERE scsegments.road_id=tmpnofnodesinsegment.road_id AND scsegments.isOneWay=false
;








ALTER TABLE scsegments ADD COLUMN nd1starde text;
ALTER TABLE scsegments ADD COLUMN nd2starde text;

UPDATE scsegments SET nd1starde=
(SELECT intersection_id
FROM roadsintersectionsnodes
WHERE nd1=node_id)
;

UPDATE scsegments SET nd2starde=
(SELECT intersection_id
FROM roadsintersectionsnodes
WHERE nd2=node_id)
;






UPDATE scsegments SET nd1starde=
(SELECT node_id
FROM roadsnodesdeadends
WHERE scsegments.nd1=roadsnodesdeadends.node_id 
)
WHERE scsegments.nd1starde IS NULL
;

UPDATE scsegments SET nd2starde=
(SELECT node_id
FROM roadsnodesdeadends
WHERE scsegments.nd2=roadsnodesdeadends.node_id
)
WHERE scsegments.nd2starde IS NULL
;






DROP TABLE IF EXISTS pathsbetweensnodes;

CREATE TABLE pathsbetweensnodes AS
WITH RECURSIVE searchnet(origin, destination, path, depth, complete, cycle) AS (
	SELECT n.nd1, n.nd2, ARRAY[n.nd1,n.nd2],1, (CASE WHEN nd2starde IS NOT NULL THEN true ELSE false END), false
	FROM scsegments n
	WHERE (n.nd1starde IS NOT NULL)

	UNION ALL
	
	SELECT n.nd1,n.nd2,path||nd2, sn.depth+1, nd2starde IS NOT NULL, n.nd2=ANY(path)
	FROM scsegments n, searchnet sn
	WHERE n.nd1=sn.destination AND NOT cycle AND n.nd1starde IS NULL
	

)
SELECT path FROM searchnet
WHERE NOT cycle AND complete;
;



DROP TABLE IF EXISTS tmppathnodes;

CREATE TABLE tmppathnodes AS
SELECT path[1] as ndorigin, path[array_length(path,1)] as nddestination, path
FROM pathsbetweensnodes
;



SELECT ndorigin, nddestination, COUNT(1) as hmt
FROM tmppathnodes
GROUP BY ndorigin, nddestination
ORDER BY hmt DESC
;






DROP TABLE IF EXISTS waypoints;

CREATE TABLE waypoints AS
	SELECT  null::bigint as wpt_id, geom, intersection_id as oldid
	FROM roadsintersections;
;



INSERT INTO waypoints
(SELECT null, geom, node_id
FROM roadsnodesdeadends)
;


ALTER TABLE waypoints
    ALTER COLUMN geom TYPE geometry(Point,4326) USING ST_Transform(geom,4326)
;

UPDATE waypoints
SET wpt_id=
(SELECT round(ST_X(geom)*10000)*1000000+round(ST_Y(geom)*10000))
;



DROP TABLE IF EXISTS waypointsclustered;

CREATE TABLE waypointsclustered AS

	SELECT DISTINCT
		wpt_id, ST_Centroid(mycollection) AS geom
	FROM
		(
			SELECT
				t1.wpt_id,ST_Collect(t1.geom) AS mycollection
			FROM
				waypoints AS t1
			GROUP BY
			t1.wpt_id
			) AS foo
;





ALTER TABLE tmppathnodes DROP COLUMN IF EXISTS starde1;
ALTER TABLE tmppathnodes DROP COLUMN IF EXISTS starde2;

ALTER TABLE tmppathnodes ADD COLUMN starde1 text;
ALTER TABLE tmppathnodes ADD COLUMN starde2 text;


UPDATE tmppathnodes SET starde1=
	(SELECT intersection_id
	FROM roadsintersectionsnodes rin
	WHERE  ndorigin=rin.node_id)
;

UPDATE tmppathnodes SET starde1=ndorigin
	WHERE starde1 IS NULL
;


UPDATE tmppathnodes SET starde2=
	(SELECT intersection_id
	FROM roadsintersectionsnodes rin
	WHERE  nddestination=rin.node_id)
;

UPDATE tmppathnodes SET starde2=nddestination
WHERE starde2 IS NULL
;


UPDATE tmppathnodes SET starde1=wpt_id
FROM waypoints
WHERE starde1=oldid
;

UPDATE tmppathnodes SET starde2=wpt_id
FROM waypoints
WHERE starde2=oldid
;


UPDATE tmppathnodes SET path[1]= starde1::bigint
;

UPDATE tmppathnodes SET path[array_length(path,1)]= starde2::bigint
;





ALTER TABLE tmppathnodes DROP COLUMN IF EXISTS fnlstarde1;
ALTER TABLE tmppathnodes DROP COLUMN IF EXISTS fnlstarde2;
ALTER TABLE tmppathnodes DROP COLUMN IF EXISTS fnldirection;
ALTER TABLE tmppathnodes DROP COLUMN IF EXISTS fnlpath;
ALTER TABLE tmppathnodes DROP COLUMN IF EXISTS fnlpathgeom;
ALTER TABLE tmppathnodes DROP COLUMN IF EXISTS fnllength;

ALTER TABLE tmppathnodes ADD COLUMN fnlstarde1 bigint;
ALTER TABLE tmppathnodes ADD COLUMN fnlstarde2 bigint;
ALTER TABLE tmppathnodes ADD COLUMN fnldirection smallint;
ALTER TABLE tmppathnodes ADD COLUMN fnlpath bigint[];
ALTER TABLE tmppathnodes ADD COLUMN fnlpathgeom geometry;
ALTER TABLE tmppathnodes ADD COLUMN fnllength integer;

CREATE OR REPLACE FUNCTION array_reverse(anyarray) RETURNS anyarray AS $$
SELECT ARRAY(
    SELECT $1[i]
    FROM generate_subscripts($1,1) AS s(i)
    ORDER BY i DESC
);
$$ LANGUAGE 'sql' STRICT IMMUTABLE;



UPDATE tmppathnodes SET
fnlstarde1=LEAST(starde1::bigint,starde2::bigint),
fnlstarde2=GREATEST(starde1::bigint,starde2::bigint),
fnlpath=(CASE WHEN LEAST(starde1::bigint,starde2::bigint)=starde1::bigint THEN path ELSE array_reverse(path) END),
fnldirection=(CASE WHEN LEAST(starde1::bigint,starde2::bigint)=starde1::bigint THEN 1 ELSE 2 END)
;

DELETE FROM tmppathnodes
WHERE fnlstarde1=fnlstarde2
;

DROP FUNCTION IF EXISTS path_mkline(anyarray);

CREATE OR REPLACE FUNCTION path_mkline(anyarray) RETURNS geometry[] AS $$

	WITH allpointscoords AS
		(
		(SELECT node_id as pointid, ST_Transform(geom,4326) as geom
		FROM roadsnodesdata)

		UNION ALL

		(SELECT wpt_id as pointid, geom
		FROM waypointsclustered)
		)

	SELECT ARRAY(
	SELECT geom
	FROM generate_subscripts($1,1) AS s(i), allpointscoords
	WHERE $1[i]=allpointscoords.pointid
	ORDER BY i
	);
$$ LANGUAGE 'sql' STRICT IMMUTABLE;


UPDATE tmppathnodes SET
fnlpathgeom=
ST_MakeLine(path_mkline(path))
;

UPDATE tmppathnodes SET
fnllength=
ST_Length(fnlpathgeom::geography)
;


ALTER TABLE tmppathnodes DROP COLUMN IF EXISTS pathid;

ALTER TABLE tmppathnodes ADD COLUMN pathid serial;








ALTER TABLE tmppathnodes DROP COLUMN IF EXISTS fnlpathbuffer;
ALTER TABLE tmppathnodes ADD COLUMN fnlpathbuffer geometry;


CREATE OR REPLACE FUNCTION utmzone(geometry)
RETURNS integer AS
$BODY$
DECLARE
geomgeog geometry;
zone int;
pref int;
 
BEGIN
geomgeog:= ST_Transform($1,4326);
 
IF (ST_Y(geomgeog))>0 THEN
pref:=32600;
ELSE
pref:=32700;
END IF;
 
zone:=floor((ST_X(geomgeog)+180)/6)+1;
 
RETURN zone+pref;
END;
$BODY$ LANGUAGE 'plpgsql' IMMUTABLE
COST 100;



CREATE OR REPLACE FUNCTION ST_Buffer_Meters(geometry, double precision)
RETURNS geometry AS
$BODY$
DECLARE
orig_srid int;
utm_srid int;
 
BEGIN
orig_srid:= ST_SRID($1);
utm_srid:= utmzone(ST_Centroid($1));
 
RETURN ST_transform(ST_Buffer(ST_transform($1, utm_srid), $2), orig_srid);
END;
$BODY$ LANGUAGE 'plpgsql' IMMUTABLE
COST 100;



UPDATE tmppathnodes SET
fnlpathbuffer=ST_Buffer_Meters(fnlpathgeom,12)
;


DROP TABLE IF EXISTS tmpsimilarpaths; 

CREATE TABLE tmpsimilarpaths AS
SELECT t1.fnlstarde1,t1.fnlstarde2,t1.pathid as pathid1,t2.pathid as pathid2, ST_Contains(t1.fnlpathbuffer,t2.fnlpathgeom) as isSimilar
FROM tmppathnodes t1, tmppathnodes t2
WHERE
t1.fnlstarde1=t2.fnlstarde1 AND t1.fnlstarde2=t2.fnlstarde2 AND t1.pathid<=t2.pathid 
;


DROP TABLE IF EXISTS tmpfillclusters; 

CREATE TABLE tmpfillclusters AS
SELECT DISTINCT fnlstarde1,fnlstarde2, pathid1 as cluster1st
FROM tmpsimilarpaths
;


ALTER TABLE tmpfillclusters ADD COLUMN clustermembers integer[];

UPDATE tmpfillclusters SET clustermembers[1]=cluster1st;

UPDATE tmpfillclusters SET clustermembers=
clustermembers || tmpsimilarpaths.pathid2
FROM tmpsimilarpaths
WHERE tmpsimilarpaths.isSimilar=true AND tmpsimilarpaths.pathid1=cluster1st AND tmpsimilarpaths.pathid2<>cluster1st
;

UPDATE tmpfillclusters SET clustermembers=
clustermembers || tmpsimilarpaths.pathid1
FROM tmpsimilarpaths
WHERE tmpsimilarpaths.isSimilar=true AND tmpsimilarpaths.pathid2=cluster1st AND tmpsimilarpaths.pathid1<>cluster1st
;


DROP TABLE IF EXISTS tmpclusters;

CREATE TABLE tmpclusters AS
	SELECT DISTINCT fnlstarde1,fnlstarde2, sort(clustermembers) as clustermembers
	FROM tmpfillclusters
;






ALTER TABLE tmpclusters DROP COLUMN IF EXISTS clusterid;
ALTER TABLE tmpclusters ADD COLUMN clusterid serial;

DELETE FROM tmpclusters
WHERE clustermembers <@ (SELECT clustermembers FROM tmpclusters WHERE clusterid<>tmpclusters.clusterid);


DROP TABLE IF EXISTS tmpclusteredpaths;
CREATE TABLE tmpclusteredpaths AS


	WITH minlengthofcluster AS
	(
		(
		WITH lengthsofmembers AS
			(
			WITH listofmembers AS
				(
				SELECT tmpclusters.clusterid, unnest(clustermembers) as pathid
				FROM tmpclusters)
			SELECT tmpclusters.clusterid,tmppathnodes.fnllength
			FROM tmpclusters,tmppathnodes,listofmembers
			WHERE 
				tmpclusters.clusterid=listofmembers.clusterid AND
				tmppathnodes.pathid=listofmembers.pathid
			)

		SELECT clusterid,min(fnllength) as clustersminlength
		FROM lengthsofmembers
		GROUP BY clusterid
		)
	)

	SELECT DISTINCT ON (clusterid)
	       tmpclusters.clusterid,   tmpclusters.fnlstarde1, tmpclusters.fnlstarde2, (tmpclusters.fnlstarde1::text || tmpclusters.fnlstarde2::text) as lnk_id, pathslist.pathid,tmppathnodes.fnlpathgeom
	FROM  tmpclusters,minlengthofcluster,tmppathnodes,(
						SELECT tmpclusters.clusterid, unnest(clustermembers) as pathid
						FROM tmpclusters
						) AS pathslist

	WHERE tmpclusters.clusterid=minlengthofcluster.clusterid AND tmpclusters.clusterid=pathslist.clusterid AND pathslist.pathid=tmppathnodes.pathid AND minlengthofcluster.clustersminlength=tmppathnodes.fnllength
	ORDER BY clusterid, tmppathnodes.pathid ASC
;






DROP TYPE IF EXISTS lnkdir CASCADE;
CREATE TYPE lnkdir AS ENUM ('bi-directional', 'lnk12', 'lnk21');

DROP TABLE IF EXISTS links;

CREATE TABLE links
	(
	lnk_id character(26),
	lnk_1 bigint,
	lnk_2 bigint,
	lnk_index smallint,
	lnk_directionality lnkdir,
	lnk_geom geometry("LINESTRING",4326),
	clusterid integer
	)
;

INSERT INTO links(lnk_id,lnk_1,lnk_2,lnk_index,lnk_directionality,lnk_geom,clusterid)

SELECT lnk_id , fnlstarde1 as lnk_1, fnlstarde2 as lnk_2, row_number() OVER (PARTITION BY lnk_id ORDER BY ST_length(fnlpathgeom) ASC) as lnk_index, NULL as lnk_directionality,  fnlpathgeom as link_geom, clusterid

FROM tmpclusteredpaths
;

UPDATE links SET lnk_id=
lnk_id || lpad(lnk_index::text,2,'0')
;




UPDATE links SET lnk_directionality=
(SELECT (CASE
	WHEN hasDir1=true AND hasDir2=true THEN 'bi-directional'::lnkdir
	WHEN hasDir1=true AND hasDir2=false THEN 'lnk12'::lnkdir
	WHEN hasDir1=false AND hasDir2=true THEN 'lnk21'::lnkdir
	END ) as lnk_directionality
FROM
	
	(

		(WITH listofmembersdirs AS
			(
			WITH listofmembers AS
					(
					SELECT tmpclusters.clusterid, unnest(clustermembers) as pathid
					FROM tmpclusters
					)
				SELECT tmpclusters.clusterid, listofmembers.pathid, tmppathnodes.fnldirection

				FROM
					tmpclusters,
					listofmembers,
					tmppathnodes
				WHERE
					tmpclusters.clusterid=listofmembers.clusterid AND
					listofmembers.pathid=tmppathnodes.pathid
			)
		SELECT tmpclusters.clusterid, bool_or(listofmembersdirs.fnldirection=1) as hasDir1, bool_or(listofmembersdirs.fnldirection=2) as hasDir2
		FROM tmpclusters,listofmembersdirs
		WHERE tmpclusters.clusterid=listofmembersdirs.clusterid
		GROUP BY tmpclusters.clusterid
		)
	) as foo
WHERE links.clusterid=foo.clusterid
)
;


ALTER TABLE links DROP COLUMN clusterid;



