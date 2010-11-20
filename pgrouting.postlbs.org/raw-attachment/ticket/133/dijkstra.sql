-- Function: dijkstra_sp(character varying, integer, integer)

CREATE OR REPLACE FUNCTION dijkstra_sp(geom_table character varying, source integer, target integer)
  RETURNS SETOF geoms AS
$BODY$
DECLARE 
	r record;
	g_rec record;
        p_rec record;
	path_result record;
	v_id integer;
	e_id integer;
	geom geoms;
	id integer;
        g_schema text;
        g_table text;
        pos int;	
BEGIN

	pos := strpos(geom_table,'.');

        if pos=0 then 
           g_schema := 'public';
  	   g_table := geom_table; 
        else 
  	   g_schema = substr(geom_table,0,pos);
  	   pos := pos + 1; 
           g_table = substr(geom_table,pos);
        END IF;

        select into g_rec f_geometry_column, type as geom_type 
          from public.geometry_columns 
          where f_table_schema = g_schema 
            and f_table_name = g_table;

       select into p_rec col.column_name as pkey 
         from information_schema.table_constraints as key, information_schema.key_column_usage as col 
         where key.table_schema = g_schema::name 
           and key.table_name = g_table::name 
           and key.constraint_type='PRIMARY KEY' 
           and key.table_catalog = col.table_catalog 
           and key.table_schema = col.table_schema 
           and key.table_name = col.table_name;

	id :=0;
	
	FOR path_result IN EXECUTE 'SELECT '||p_rec.pkey||' as gid,'||g_rec.f_geometry_column||' as the_geom FROM ' ||
          'shortest_path(''SELECT '||p_rec.pkey||' as id, source::integer, target::integer, ' || 
          'length::double precision as cost FROM ' ||
	  quote_ident(g_schema)||'.'||quote_ident(g_table) || ''', ' || quote_literal(source) || 
          ' , ' || quote_literal(target) || ' , false, false), ' || 
          quote_ident(g_schema)||'.'||quote_ident(g_table) || ' where edge_id = '||p_rec.pkey
        LOOP

                 geom.gid      := path_result.gid;
                 geom.the_geom := path_result.the_geom;
		 id := id+1;
		 geom.id       := id;
                 
                 RETURN NEXT geom;

	END LOOP;
	RETURN;
END;
$BODY$
  LANGUAGE 'plpgsql' VOLATILE STRICT
  COST 100
  ROWS 1000;

