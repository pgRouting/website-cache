CREATE OR REPLACE FUNCTION split_parallel_edges(
       varchar, varchar, varchar, integer) 
       RETURNS VOID AS
$$
DECLARE 
        tbl ALIAS FOR $1;
	gid_seq ALIAS FOR $2;
	v_seq ALIAS FOR $3;
	count ALIAS FOR $4;

	row record;
	r record;
	
	gid integer;
	
	source integer;
	target integer;
	p_source integer;
	p_target integer;
	
	x1 double precision;
	y1 double precision;
	x2 double precision;
	y2 double precision;
	
        geom geometry;
	muid integer;
	class_id integer;
	length double precision;
	reverse_cost double precision;
	
	l1 geometry;
	l2 geometry;
	
	v_max integer;
	gid_max integer;
	
	s_max integer;
	t_max integer;
	
	srid integer;
	
BEGIN
	
        FOR row IN EXECUTE
            'select srid(the_geom) from ' ||tbl|| ' limit 1'
        LOOP
        END LOOP;
        srid := row.srid;
	
	FOR row IN EXECUTE 'select max(gid) as max from '||tbl LOOP
	END LOOP;
	
	gid_max := row.max;

	FOR row IN EXECUTE 'select max(source) as max from '||tbl LOOP
	END LOOP;
	
	s_max := row.max;

	FOR row IN EXECUTE 'select max(target) as max from '||tbl LOOP
	END LOOP;
	
	t_max := row.max;

	IF s_max > t_max THEN
	    v_max := s_max;
	ELSE
	    v_max := t_max;
	END IF;
	
	
	EXECUTE 'drop sequence '||v_seq;
	EXECUTE 'drop sequence '||gid_seq;	

	EXECUTE 'create sequence '||v_seq||' start '||v_max;
	EXECUTE 'create sequence '||gid_seq||' start '||gid_max;	
	
	p_source := 0;
	p_target := 0;
	
	FOR row IN EXECUTE 'select gid, the_geom, id, source, target,x1,y1,x2,y2,class_id,length,reverse_cost from '||tbl||
				    ' where (source, target) in (select source, target from '||tbl||
				    ' t2 group by source, target having count(*)>'||count||') order by source, target, length' 
        LOOP

                 gid := row.gid;
                 geom := row.the_geom;
		 source := row.source;
		 target := row.target;
		 muid := row.id;
		 x1 := row.x1;
		 y1 := row.y1;
		 x2 := row.x2;
		 y2 := row.y2;
		 length := row.length;
		 class_id := row.class_id;
		 reverse_cost := row.reverse_cost;
		 
		 IF source = p_source AND target=p_target THEN
		    l1 := setsrid(line_substring(linemerge(geom), 0, 0.5), srid);
		    l2 := setsrid(line_substring(linemerge(geom), 0.5, 1), srid);
		    
		    RAISE NOTICE 'gid=%',gid;
		    
		    EXECUTE 'delete from '||tbl||' where gid = '||gid;
		    
		    EXECUTE 'insert into '||tbl||' (gid, the_geom, x1,y1,x2,y2,source, target,id, length, reverse_cost, class_id) '||
					'values ('||gid||', multi(geomfromtext('''||astext(l1)||''','||srid||')), '||x1||', '||y1||', '||
					x(endpoint(l1))||', '||y(endpoint(l1))||','||
					source||', (select nextval('''||v_seq||''')), '||muid||', '||length/2||
					', '||reverse_cost/2||', '||class_id||')';

		    EXECUTE 'insert into '||tbl||' (gid, the_geom, x1,y1,x2,y2,source, target,id, length, reverse_cost, class_id) '||
					'values ((select nextval('''||gid_seq||''')), multi(geomfromtext('''||astext(l2)||''','||srid||')), '||
					x(endpoint(l2))||', '||y(endpoint(l2))||','||
					x2||', '||y2||', (select currval('''||v_seq||''')), '||target||', '||muid||', '||length/2||
					', '||reverse_cost/2||', '||class_id||')';
		 ELSE
		    p_source = source;
		    p_target = target;
		 END IF;

        END LOOP;
        RETURN;
END;
$$
LANGUAGE 'plpgsql' VOLATILE STRICT; 
