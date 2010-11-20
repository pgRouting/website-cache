--
-- Copyright (c) 2005 Sylvain Pasche,
--               2006-2007 Anton A. Patrushev, Orkney, Inc.
--
-- This program is free software; you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation; either version 2 of the License, or
-- (at your option) any later version.
--
-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.
--
-- You should have received a copy of the GNU General Public License
-- along with this program; if not, write to the Free Software
-- Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.
--


CREATE TYPE path_result AS (vertex_id integer, edge_id integer, cost float8);
CREATE TYPE vertex_result AS (x float8, y float8);

-----------------------------------------------------------------------
-- Core function for shortest_path computation
-- See README for description
-----------------------------------------------------------------------
CREATE OR REPLACE FUNCTION shortest_path(sql text, source_id integer, 
        target_id integer, directed boolean, has_reverse_cost boolean)
        RETURNS SETOF path_result
        AS '$libdir/librouting'
        LANGUAGE 'C' IMMUTABLE STRICT;

-----------------------------------------------------------------------
-- Core function for shortest_path_astar computation
-- Simillar to shortest_path in usage but uses the A* algorithm
-- instead of Dijkstra's.
-----------------------------------------------------------------------
CREATE OR REPLACE FUNCTION shortest_path_astar(sql text, source_id integer, 
        target_id integer,directed boolean, has_reverse_cost boolean)
         RETURNS SETOF path_result
         AS '$libdir/librouting'
         LANGUAGE 'C' IMMUTABLE STRICT; 

-----------------------------------------------------------------------
-- Core function for shortest_path_astar computation
-- Simillar to shortest_path in usage but uses the Shooting* algorithm
-----------------------------------------------------------------------
CREATE OR REPLACE FUNCTION shortest_path_shooting_star(sql text, source_id integer, 
        target_id integer,directed boolean, has_reverse_cost boolean)
         RETURNS SETOF path_result
         AS '$libdir/librouting'
         LANGUAGE 'C' IMMUTABLE STRICT; 

-----------------------------------------------------------------------
-- This function should not be used directly. Use create_graph_tables instead
--
-- Insert a vertex into the vertices table if not already there, and
--  return the id of the newly inserted or already existing element
-----------------------------------------------------------------------
CREATE OR REPLACE FUNCTION insert_vertex(vertices_table varchar, 
       geom_id int) 
       RETURNS int AS
$$
DECLARE
        vertex_id int;
        myrec record;
BEGIN
        LOOP
          FOR myrec IN EXECUTE 'SELECT id FROM ' || 
                     quote_ident(vertices_table) || 
                     ' WHERE geom_id = ' || quote_literal(geom_id)  LOOP

                        IF myrec.id IS NOT NULL THEN
                                RETURN myrec.id;
                        END IF;
          END LOOP; 
          EXECUTE 'INSERT INTO ' || quote_ident(vertices_table) || 
                  ' (geom_id) VALUES (' || quote_literal(geom_id) || ')';
        END LOOP;
END;
$$
LANGUAGE 'plpgsql' VOLATILE STRICT; 


-----------------------------------------------------------------------
-- Create the vertices and edges tables from a table matching the 
--  geometry schema described above.
-----------------------------------------------------------------------
CREATE OR REPLACE FUNCTION create_graph_tables(geom_table varchar) 
       RETURNS void AS
$$
BEGIN
		EXECUTE 'SELECT create_graph_tables('''||quote_ident(geom_table)||''',''int4'',' || '''gid'' ,''source_id'',''target_id'')';
END;
$$
LANGUAGE 'plpgsql' VOLATILE STRICT;

CREATE OR REPLACE FUNCTION create_graph_tables(geom_table varchar, 
       column_type varchar )
       RETURNS void AS
$$
BEGIN
		EXECUTE 'SELECT create_graph_tables('''||quote_ident(geom_table)||''','''||quote_ident(column_type)||''',' || '''gid'' ,''source_id'',''target_id'')';
END;
$$
LANGUAGE 'plpgsql' VOLATILE STRICT;

CREATE OR REPLACE FUNCTION create_graph_tables(geom_table varchar, 
       column_type varchar , id_name varchar)
       RETURNS void AS
$$
BEGIN
		EXECUTE 'SELECT create_graph_tables('''||quote_literal(geom_table)||''','''||quote_literal(column_type)||''',''' || quote_literal(id_name) || ''' ,''source_id'',''target_id'')';
	RETURN;
END;
$$
LANGUAGE 'plpgsql' VOLATILE STRICT;




CREATE OR REPLACE FUNCTION create_graph_tables(geom_table varchar, 
       column_type varchar, id_name varchar,source_name varchar,target_name varchar)
       RETURNS void AS
$$
DECLARE
        geom record;
        edge_id int;
        myrec record;
        source_id int;
        target_id int;
        vertices_table varchar := quote_ident(geom_table) || '_vertices';
        edges_table varchar := quote_ident(geom_table) || '_edges';
BEGIN

        EXECUTE 'CREATE TABLE ' || vertices_table || 
                ' (id serial, geom_id ' || quote_ident(column_type) || 
                '  NOT NULL UNIQUE)';

        EXECUTE 'CREATE INDEX ' || vertices_table || '_id_idx on ' || 
                vertices_table || ' (id)';

        EXECUTE 'CREATE TABLE ' || edges_table || 
                ' (id serial, source int, target int, ' || 
                'cost float8, reverse_cost float8, UNIQUE (source, target))';

        EXECUTE 'CREATE INDEX ' || edges_table || 
                '_source_target_idx on ' || edges_table || 
                ' (source, target)';

		BEGIN
			EXECUTE 'ALTER TABLE ' || quote_ident(geom_table) ||' ADD COLUMN edge_id int4';
		EXCEPTION 
			WHEN DUPLICATE_COLUMN THEN
		END;


        FOR geom IN EXECUTE 'SELECT '|| quote_ident(id_name) ||' as id, ' || 
				quote_ident(source_name) ||
             ' AS source, ' || 
				quote_ident(target_name) ||
             ' AS target FROM ' || quote_ident(geom_table) LOOP

                SELECT INTO source_id insert_vertex(vertices_table, 
                                                    geom.source);

                SELECT INTO target_id insert_vertex(vertices_table, 
                                                    geom.target);

                BEGIN
                    EXECUTE 'INSERT INTO ' || edges_table || 
                            ' (source, target) VALUES ('  || 
                            quote_literal(source_id) || ', ' || 
                            quote_literal(target_id) || ')';

                EXCEPTION 
                        WHEN UNIQUE_VIOLATION THEN
                END;

                FOR myrec IN EXECUTE 'SELECT id FROM ' || edges_table || 
                    ' e WHERE ' || ' e.source = ' || 
                    quote_literal(source_id) || 
                    ' and e.target = ' || 
                    quote_literal(target_id) LOOP
                END LOOP; 

                edge_id := myrec.id;

                IF edge_id IS NULL OR edge_id < 0 THEN
                        RAISE EXCEPTION 'Bad edge id';
                END IF;

                EXECUTE 'UPDATE ' || quote_ident(geom_table) || 
                        ' SET edge_id = ' || edge_id || 
                        ' WHERE ' || quote_ident(id_name) || ' =  ' || geom.id;
        END LOOP;
        RETURN;
END;
$$
LANGUAGE 'plpgsql' VOLATILE STRICT;

-----------------------------------------------------------------------
-- Compute the shortest path using edges and vertices table, and return
--  the result as a set of (gid integer, the_geom gemoetry) records.
-- This function uses the internal vertices identifiers.
-----------------------------------------------------------------------
CREATE OR REPLACE FUNCTION shortest_path_as_geometry_internal_id(
       geom_table varchar, source int4, target int4) 
       RETURNS SETOF GEOMS AS
$$
DECLARE 
	r record;
	path_result record;
	v_id integer;
	e_id integer;
	geom geoms;
BEGIN
	
	FOR path_result IN EXECUTE 'SELECT gid,the_geom FROM ' ||
          'shortest_path(''SELECT gid as id, source::integer, target::integer, ' || 
          'length::double precision as cost FROM ' ||
	  quote_ident(geom_table) || ''', ' || quote_literal(source) || 
          ' , ' || quote_literal(target) || ' , false, false), ' || 
          quote_ident(geom_table) || ' where edge_id = gid ' 
        LOOP

                 geom.gid      := path_result.gid;
                 geom.the_geom := path_result.the_geom;
                 
                 RETURN NEXT geom;

	END LOOP;
	RETURN;
END;
$$
LANGUAGE 'plpgsql' VOLATILE STRICT; 

CREATE OR REPLACE FUNCTION shortest_path_as_geometry_internal_id_directed(
       geom_table varchar, source int4, target int4, dir boolean, rc boolean) 
       RETURNS SETOF GEOMS AS
$$
DECLARE 
	r record;
	path_result record;
	v_id integer;
	e_id integer;
	geom geoms;
	query text;
BEGIN
	
	query := 'SELECT gid,the_geom FROM ' ||
          'shortest_path(''SELECT gid as id, source::integer, target::integer, ' || 
          'length::double precision as cost ';
	  
	IF rc THEN query := query || ', reverse_cost ';  
	END IF;
	
	query := query || 'FROM ' ||  quote_ident(geom_table) || ''', ' || quote_literal(source) || 
          ' , ' || quote_literal(target) || ' , '''||dir||''', '''||rc||'''), ' || 
          quote_ident(geom_table) || ' where edge_id = gid ';

	FOR path_result IN EXECUTE query
        LOOP

                 geom.gid      := path_result.gid;
                 geom.the_geom := path_result.the_geom;
                 
                 RETURN NEXT geom;

	END LOOP;
	RETURN;
END;
$$
LANGUAGE 'plpgsql' VOLATILE STRICT; 

-----------------------------------------------------------------------
-- Compute the shortest path using edges and vertices table, and return
--  the result as a set of (gid integer, the_geom gemoetry) records.
-----------------------------------------------------------------------
CREATE OR REPLACE FUNCTION shortest_path_as_geometry(geom_table varchar, 
       geom_source anyelement,geom_target anyelement) 
       RETURNS SETOF GEOMS AS
$$
DECLARE 
	r record;
	source int4;
	target int4;
	path_result record;
	v_id integer;
	e_id integer;
	geom geoms;
BEGIN
	FOR r IN EXECUTE 'SELECT id FROM ' || quote_ident(geom_table) || 
           '_vertices WHERE geom_id = ' || quote_literal(geom_source) LOOP

		source = r.id;

	END LOOP;

	IF source IS NULL THEN
		RAISE EXCEPTION 'Can''t find source edge';
	END IF;

	FOR r IN EXECUTE 'SELECT id FROM ' || quote_ident(geom_table) || 
            '_vertices WHERE geom_id = ' || quote_literal(geom_target) LOOP
		target = r.id;
	END LOOP;

	IF target IS NULL THEN
		RAISE EXCEPTION 'Can''t find target edge';
	END IF;
	
	FOR geom IN SELECT * FROM 
          shortest_path_as_geometry_internal_id(geom_table, 
                                                source, target) LOOP
		RETURN NEXT geom;
	END LOOP;

	RETURN;
END;
$$
LANGUAGE 'plpgsql' VOLATILE STRICT; 



