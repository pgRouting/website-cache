drop view topology;
/* ways */
drop table ways;
create table ways as (
select 
id as gid, 
length_spheroid( planet_osm_line.way, 'SPHEROID["WGS 84",6378137,298.257223563,AUTHORITY["EPSG","7030"]]') as length,
name,
way as the_geom,
nodes[array_lower(nodes,1)] as sourcenode, 
nodes[array_upper(nodes,1)] as targetnode
from 
planet_osm_ways, 
planet_osm_line 
where 
planet_osm_line.osm_id = planet_osm_ways.id 
and not planet_osm_line.highway is null);

alter table ways ADD CONSTRAINT ways_pk PRIMARY KEY (gid);
alter table ways ADD CONSTRAINT enforce_dims_the_geom CHECK (ndims(the_geom) = 2);
alter table ways ADD CONSTRAINT enforce_geotype_the_geom CHECK (geometrytype(the_geom) = 'LINESTRING'::text OR the_geom IS NULL);
alter table ways ADD CONSTRAINT enforce_srid_the_geom CHECK (srid(the_geom) = 4326);

ALTER TABLE ways ADD COLUMN source integer;
ALTER TABLE ways ADD COLUMN target integer;
ALTER TABLE ways ADD COLUMN x1 double precision;
ALTER TABLE ways ADD COLUMN y1 double precision;
ALTER TABLE ways ADD COLUMN x2 double precision;
ALTER TABLE ways ADD COLUMN y2 double precision;
UPDATE ways SET x1 = x(startpoint(the_geom));
UPDATE ways SET y1 = y(startpoint(the_geom));
UPDATE ways SET x2 = x(endpoint(the_geom));
UPDATE ways SET y2 = y(endpoint(the_geom));
ALTER TABLE ways ADD COLUMN reverse_cost double precision;
UPDATE ways SET reverse_cost = length;
ALTER TABLE ways ADD COLUMN to_cost double precision;
ALTER TABLE ways ADD COLUMN rule text;

CREATE INDEX source_idx ON ways(source);
CREATE INDEX target_idx ON ways(target);
CREATE INDEX geom_idx ON ways USING GIST(the_geom GIST_GEOMETRY_OPS);

drop table vertices_tmp;
SELECT assign_vertex_id('ways', 0.00001, 'the_geom', 'gid');

/* nodes */
DROP TABLE nodes;
CREATE TABLE nodes as 
select id as gid, geomfromtext('POINT(' || cast(lon as float) / 10000000 || ' ' || cast(lat as float) / 10000000 || ')', 4326) as the_geom from planet_osm_nodes;
alter table nodes ADD CONSTRAINT nodes_pk PRIMARY KEY (gid);
alter table nodes ADD CONSTRAINT enforce_dims_the_geom CHECK (ndims(the_geom) = 2);
alter table nodes ADD CONSTRAINT enforce_geotype_the_geom CHECK (geometrytype(the_geom) = 'POINT'::text OR the_geom IS NULL);
alter table nodes ADD CONSTRAINT enforce_srid_the_geom CHECK (srid(the_geom) = 4326);

select probe_geometry_columns();


/* latency */
drop table latency;
create table latency as select id, the_geom,
(select count(*) from ways where vertices_tmp.id = source or vertices_tmp.id = target) as count from vertices_tmp order by count;
alter table latency add constraint latency_pk PRIMARY KEY (id);

/* topology */

create view topology as select 
	gid,
	--source,
	--slcy.count as source_latency, 
	--target,
	--tlcy.count as target_latency,
	ways.the_geom,
	CASE 
	WHEN slcy.count = 1 AND tlcy.count = 1 THEN 'Detached' 
	WHEN slcy.count = 1 AND tlcy.count > 1 THEN 'Cul de Sac' 
	WHEN slcy.count > 1 AND tlcy.count = 1 THEN 'Cul de Sac'
	WHEN slcy.count > 1 AND tlcy.count > 1 THEN NULL
	WHEN source = target THEN 'Loop'
	END as network_type
from ways, latency as slcy, latency as tlcy 
where source = slcy.id and target = tlcy.id order by network_type;

update ways set reverse_cost = length;
update ways set to_cost = length;
update ways set reverse_cost = 999999 from planet_osm_line where planet_osm_line.osm_id = ways.gid AND lower(oneway) = 'yes';
update ways set reverse_cost = 999999 from planet_osm_line where planet_osm_line.osm_id = ways.gid AND lower(oneway) = 'yes';
update ways set reverse_cost = 999999 from planet_osm_line where planet_osm_line.osm_id = ways.gid AND lower(oneway) = 'true';
update ways set to_cost = 999999 from planet_osm_line where planet_osm_line.osm_id = ways.gid AND lower(oneway) = '-1';
