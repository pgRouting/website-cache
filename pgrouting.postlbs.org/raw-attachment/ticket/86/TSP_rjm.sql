--
-- Definitions for TSP/VRP with constraints.
--
-- Copyright(c) Rod Millar 2008
-- email: rodj59@yahoo.com.au , rodj59@y7.com.au
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

create type total_type as (
    total_dist float(4),
    total_time	interval,
    inconsistent_priority double precision,
    consistent_priority	  double precision,
    inconsistencies	float(4),
    consistencies	int,
    non_dist_inconsistencies	int
);

create type time_dist_type as (
    time interval,
    dist float(4)
);
create type path_dest_type as(
    job		int,		-- job number
    pu		boolean,	-- t if is PU destination, f if is Drop 
    suburb	varchar,	
    city	varchar,
    time	timestamp,	-- scheduled reaching of the destination
    time_bound	timestamp,	-- earliest PU or latest Drop time limit
    dist	float(4),	-- cumulative distance along path
    priority	double precision,
    seq		int ,-- the sequence number in original path
    load_pcnt	float(4),	-- cumulative load as percentage of capacity
    job_type	varchar(1)	-- P/H/F/S/E =  point2point/Hourly/Furn/StartofDay/EndofDay
);
create type inconsistent_path_dest_type as(
    job		int,		-- job number
    pu		boolean,	-- t if is PU destination, f if is Drop 
    suburb	varchar,	
    city	varchar,
    time	timestamp,	-- scheduled reaching of the destination
    time_bound	timestamp,	-- earliest PU or latest Drop time limit
    dist	float(4),	-- cumulative distance along path
    priority	double precision,
    seq		int ,-- the sequence number in original path
    load_pcnt	float(4),	-- cumulative load as percentage of capacity
    job_type	varchar(1),	-- P/H/F/S/E =  point2point/Hourly/Furn/StartofDay/EndofDay
    flag	bit(7)		-- bit pattern to indicate type(s) of inconsistency
);

create type path_links_type as(
    prev_dest	int,		-- preceding path_dest in current path
    next_dest	int,		-- next path_dest in current path
    dist	float(4),	-- distance travel between prev and next for job
    time_int	interval,	-- time to traverse the distance prev to next for the job
    priority	double precision, -- dynamic priority
    active	boolean		-- t if link is part of the current path
);

create type path_links_oid  as (-- NB. OID methods are not presently used !!! XXX HERE 
    prev_dest	int,		-- preceding path_dest in current path
    next_dest	int,		-- next path_dest in current path
    dist	float(4),	-- distance travel between prev and next for job
    time_int	interval,	-- time to traverse the distance prev to next for the job
    priority	double precision, -- dynamic priority
    active	boolean,		-- t if link is part of the current path
    oid		int		-- the oid of the DB row (NB. system bug in plpythonu necessitates this)
);


create table debug_table (
    msg 	varchar,	-- debug message
    number	int8		-- sequence number
);

create table path_job ( 
    job	int primary key,	-- the job number
    load_pcnt	float(4),	-- the percentage of vehicle capacity onboard
    direct_dist	float(4),	-- direct distance of the job
    time_int	interval,	-- total/loading time for the job
    job_type	varchar(1),	-- P/H/F/S/E  .. S = start of day, E = endofday
    priority	double precision -- priority of the job in search
);

--
-- leave out the pre_link/next_link if feeding into Anton's Gaul based TSP
--
create table path_dest (
    job		int,		-- job number
    pu		boolean,	-- t if is PU destination, f if is Drop 
    suburb	varchar,	
    city	varchar,
    time	timestamp,	-- scheduled reaching of the destination
    time_bound	timestamp,	-- earliest PU or latest Drop time limit
    dist	float(4),	-- cumulative distance along path
    priority	double precision,
    seq		int primary key,-- the sequence number in original path
    load_pcnt	float(4),	-- cumulative load as percentage of capacity
    job_type	varchar(1)	-- P/H/F/S/E =  point2point/Hourly/Furn/StartofDay/EndofDay
);
create index path_jindx on path_dest (job);

--
-- 
--
create table path_links (
    prev_dest	int,		-- preceding path_dest in current path
    next_dest	int,		-- next path_dest in current path
    dist	float(4),	-- distance travel between prev and next for job
    time_int	interval,	-- time to traverse the distance prev to next for the job
    active	boolean,	-- t if link is part of the current path
    priority	double precision, -- dynamic priority
    primary key (prev_dest,next_dest)
);


-- priority scaled by number of distinct types of inconsistency detected
create or replace function priority_value(tab varchar,link_tab varchar,seq int,max_dist float(4),dist float(4))
    returns float(8) as
$$
    scale=plpy.execute("select inconsistency_scale('%s','%s',%s,%s,%f) * priority as icon from %s where seq = %s" % \
		(tab,link_tab,seq,max_dist,dist,tab,seq))[0]
    return scale * r['priority']
$$ language 'plpythonu' volatile strict;

-- number of distinct types of inconsistency detected on a destination
create or replace function inconsistency_scale(tab varchar,link_tab varchar,seq int,max_dist float,dist float)
    returns float(8) as
$$
    r=plpy.execute("select inconsistency_class('%s','%s',%s,%f) as icon " % \
		(tab,link_tab,seq,max_dist))[0]
    count = r['icon'].count('1')
    if r['icon'][0] == '1':
	count = count -1 + (dist / (max_dist * 2))
    return count
$$ language 'plpythonu' volatile strict;

--
-- Find the total distance travelled,total time, total inconsistencies for a particular path
-- eg. invoke as "select * from totals('path_links')" 
create or replace function totals(tab varchar,link_tab varchar,max_dist float)
    returns total_type as
$$
declare
    record1 record;
    record2 record;
    record3 record;
    dist_inconsistencies_rec record;
    res	total_type;
    tot int;
begin
    -- NB. benign bugfix required HERE XXXX
    -- ... the distance & time will be wrong for hourly jobs ... but doesn't matter w.r.t. 
    --	   strategic choices since static !!!  ... so is it worth fixing ???
    -- select only non-ceiling ie. positive priorities
    execute 'select sum(dist) as distance,sum(time_int) as time from '||
	    quote_ident(link_tab)||' where active '
	into record1;
    execute 'select count(dist) as cnt ,sum(priority)' ||
		' as priority from '||quote_ident(tab)||
	    ' where consistent('||quote_literal(tab)||
	    ','||quote_literal(link_tab)||',seq,'||max_dist||')'
	into record2;
    res.total_dist := record1.distance;
    res.total_time := record1.time;
    res.consistencies := record2.cnt ;
    execute 'select count(*) as tot,sum(priority*inconsistency_scale('||
	    quote_literal(tab)||','||quote_literal(link_tab)||',seq,'||max_dist||
	    ','||res.total_dist||')) as priority , '
	    ||' sum(inconsistency_scale('||
	    quote_literal(tab)||','||quote_literal(link_tab)||',seq,'||max_dist||
	    ','||res.total_dist||')) as ics from '||quote_ident(tab) 
	into record3;
    -- count individual inconsistency types
    res.inconsistencies := record3.ics; 
    res.consistent_priority := record2.priority;
    res.inconsistent_priority := record3.priority ;

    execute 'select count(seq) as cnt,sum(inconsistency_scale('||
		quote_literal(tab)||','||quote_literal(link_tab)||',seq,'||max_dist||
		','||res.total_dist||')) as tot from '||quote_ident(tab)||
		' where inconsistency_class('||quote_literal(tab)||
		    ','||quote_literal(link_tab)||',seq,'||max_dist||
		    ') = B''1000000'''
	into dist_inconsistencies_rec;

    execute 'select count(seq) from '||quote_ident(tab)
	into tot;
    -- non_dist_inconsistencies excludes inconsistencies which are distance_only
    res.non_dist_inconsistencies := tot - res.consistencies - dist_inconsistencies_rec.cnt;

    return res;
end;
$$
language 'plpgsql' volatile strict;


--
-- classify the type of inconsistency
-- binary flag in the following field position ->
--	0 = distance
--	1 = time  (ie. delivery too late, NB. PU too early never happens !)
-- 	2 = load
-- 	3 = drop before pickup
--	4 = PU & Drop on different days
--	5 = missing predecessor link
-- 	6 = missing successor link
-- 
-- eg 0010000 = load inconsistency only
create or replace function inconsistency_class(tab varchar,link_tab varchar,seq int,max_dist float)
    returns bit(7) as
$$
declare
    row1 path_dest;
    row2 path_dest;
    flag boolean;
    count int;
    ans bit(7);
begin
    ans := B'0000000';
    execute 'select * from '||quote_ident(tab)||' where seq = '||seq
	into row1;
    if row1.dist > max_dist
    then
	-- distance inconsistency
	ans := B'1000000';
    end if;
    if row1.job_type in ('e','E')
    then
	-- the end-of-day destination 
	if row1.time <> row1.time_bound
	then
	    ans := ans | B'0100000';
	end if;
    end if;
    if row1.job_type in ('p','P','h','H','f','F')
    then
	-- eg. a PU or Drop of a normal job
	if row1.load_pcnt > 1.0
	then
	    -- load inconsistency
	    ans := ans | B'0010000';
	end if;
	-- find the other destination of the job
	execute 'select * from '||quote_ident(tab)||' where seq != '||seq||
		' and job = '||row1.job
	    into row2;
	if row1.pu = 't' 
	then
	    -- a pickup
	    -- .. check for drop after pickup
	    execute 'select time < '''||row1.time||'''::timestamp from '||quote_ident(tab)||
			' where job = '||row1.job||' and pu is false'
		into flag;
	    if flag 
	    then
		-- drop before pickup inconsistency
		ans := ans | B'0001000';
	    end if;
	    -- see if there is any Home destination between the two destinations
	    execute 'select count(seq) from '||quote_ident(tab)||' where job_type in (''S'',''s'',''E'',''e'') and time > '''||
			row1.time||'''::timestamp and time < '''||row2.time||'''::timestamp'
		into count;
	    if count > 0
		then
		    -- PU & drop on different days inconsistency
		    ans := ans | B'0000100';
	    end if;
	else
	    -- a drop
	    execute 'select time > '''||row1.time||'''::timestamp from '||quote_ident(tab)||
			' where job = '||row1.job||' and pu is true'
		into flag;
	    if flag 
	    then
		-- drop before pickup inconsistency
		ans := ans | B'0001000';
	    end if;
	    execute 'select '''||row1.time||'''::timestamp > '''||row1.time_bound||'''::timestamp'
		into flag;
	    if flag
	    then
		-- delivery too late inconsistency
		ans := ans | B'0100000';
	    end if;
	    -- see if there is any Home destination between the two destinations
	    execute 'select count(seq) from '||quote_ident(tab)||' where job_type in (''S'',''s'',''E'',''e'') and time > '''||
			row2.time||'''::timestamp and time < '''||row1.time||'''::timestamp'
		into count;
	    if count > 0
		then
		    -- PU & drop on different days inconsistency
		    ans := ans | B'0000100';
	    end if;
	end if;
	-- see if both prev & next destinations are linked to this destination
	execute 'select count(*) from '||quote_ident(link_tab)||' where ( prev_dest = '||
		    row1.seq||' ) and active'
	    into count;
	if count  != 1
	    then
		ans := ans | B'0000001';
	end if;
	execute 'select count(*) from '||quote_ident(link_tab)||' where ( '||
		    '  next_dest = '||row1.seq||') and active'
	    into count;
	if count != 1
	    then
		ans := ans | B'0000010';
	end if;
    end if;
    -- no inconsistencies detected
    return ans;
end;
$$
language 'plpgsql' volatile strict;
-- 
-- Test if a destination is consistent. 
-- eg.  select * from consistent('path_dest',seq_no,max_dist)
--
create or replace function consistent(tab varchar , link_tab varchar, seq int,max_dist float)
    returns boolean as
$$
declare
    flag int;
begin
    execute 'select * from inconsistency_class('||quote_literal(tab)||','||quote_literal(link_tab)||','||seq||','||max_dist||')'
	into flag;
    return flag = 0;
end;
$$
language 'plpgsql' volatile strict;


-- 
-- Find the set of path_links records representing potential predecessor destination
-- links for the given destination.
-- eg. select * from prev_links('path_links',seq_no,active_flag  't'|'f')
--
create or replace function prev_links(tab varchar,seqno int,active varchar)
    returns setof path_links as
$$
declare
    row path_links;
begin
    for row in execute 'select * from '||quote_ident(tab)||' where '||
		'  active = '||quote_literal(active)||'::bool and next_dest = '|| seqno 
    loop
	return next row;
    end loop;
    return;
end;
$$
language 'plpgsql' volatile strict;
create or replace function prev_links_oid(tab varchar,oid int,active varchar)
    returns setof path_links as
$$
declare
    row path_links;
begin
    for row in execute 'select * from '||quote_ident(tab)||' where '||
		'  active = '||quote_literal(active)||'::bool and oid = '|| oid 
    loop
	return next row;
    end loop;
    return;
end;
$$
language 'plpgsql' volatile strict;
create or replace function prev_links_oid(tab varchar,oid int)
    returns setof path_links as
$$
declare
    row path_links;
begin
    for row in execute 'select * from '||quote_ident(tab)||' where '||
		' oid = '|| oid 
    loop
	return next row;
    end loop;
    return;
end;
$$
language 'plpgsql' volatile strict;



-- ditto for successor destinations

create or replace function next_links(tab varchar,seqno int,active varchar)
    returns setof path_links as
$$
declare
    row path_links;
begin
    for row in execute 'select * from '||quote_ident(tab)||
		' where active = '||quote_literal(active)||'::bool and prev_dest = '|| seqno 
    loop
	return next row;
    end loop;
    return;
end;
$$
language 'plpgsql' volatile strict;

--

--
-- Find the actual travel/wait time interval for a destination from its predecessor
-- given the current active path_links records
-- ... takes the time for the previous destination, adds the path_links time & then takes max of 
-- that & the earliest allowable pickup time ( in the case of a pickup ) or earliest home
-- time in the case of the pm_home destination
--
create or replace function dest_time(tab varchar,link_tab varchar,job_tab varchar,seq int)
    returns time_dist_type as
$$
declare
    rec1 record;
    row1 record;
    td   time_dist_type;
begin
    -- compute the timeinterval based on previous active def + path_links interval
    execute 'select * from '||quote_ident(tab)||' where seq = '||seq
	into row1;

    if row1.job_type in ('s','S')
	then
	-- this is a start-of-day destination, we require a 12-hour minimum gap from previous days close XXX WARNING HERE XXX
	execute 'select  greatest(''12:00:00''::interval + b.time,'''||row1.time_bound||'''::timestamp) - b.time as time,a.dist as dist from '||
		quote_ident(link_tab)||' a,'||quote_ident(tab)||' b where a.active and a.prev_dest = b.seq and a.next_dest = '||
		row1.seq
	    into rec1;
    else 
	if row1.pu or row1.job_type in ('e','E')
	then
	-- means we must not return a time less than time-bound
	execute 'select  greatest(a.time_int + b.time,'''||row1.time_bound||'''::timestamp) - b.time as time,a.dist as dist from '||
		quote_ident(link_tab)||' a,'||quote_ident(tab)||' b where a.active and a.prev_dest = b.seq and a.next_dest = '||
		row1.seq
	    into rec1;
	elsif row1.job_type not in ('p','P','s','S') and not row1.pu
	    then
		-- means this is the Drop destination of an hourly job (H/F) whose duration & distance is fixed
		--    ... and whose direct predecessor is necessarily same jobs PU destination ...
		execute 'select direct_dist as dist,time_int as time from '||quote_ident(job_tab)||'   where job = '||row1.job
		    into rec1;
	else
	    -- means we return whatever time we get
	    execute 'select  a.time_int  as time,a.dist as dist from '||
		quote_ident(link_tab)||' a,'||quote_ident(tab)||' b where a.active and  a.next_dest = '||
		row1.seq
	    into rec1;
	end if;
    end if;

    td.time := rec1.time;
    td.dist := rec1.dist;
   return td;
end;
$$
language 'plpgsql' volatile strict;


--
-- Find the actual travel/wait timestamp for each destination 
-- given the current active path_links records
-- ... walks from given seq # forward until no changes are required or
-- until the final destination is reached & applies changes as needed.
-- NB. seqno should be that of the predecessor to the changed link
-- Returns # of changes made.
create or replace function dest_changes(tab varchar,link_tab varchar,job_tab varchar,seq_no int)
    returns int as
$$
declare
    cur_dest_rec record;
    next_links_rec record;
    next_dest_ts_rec record;
    next_dest_rec record;
    next_dest_job_rec record;
    cur_dest_job_rec record;
    change_cnt int;
    final_seqno int;
    td  time_dist_type;
    dist float(4);
    load float(4); 
    seq  int;

begin
    -- compute the timeinterval based on previous active def + path_links interval

    -- find the final destination in the path (ie. an 'e' node)
    execute 'select seq from '||quote_ident(tab)||' where job_type in (''s'',''S'',''e'',''E'')  and seq <> 1 order by time_bound desc limit 1'
	into final_seqno;

    -- start at the specified seq no 
    seq := seq_no;
    change_cnt := 0;

    execute 'select time,dist,load_pcnt,job,pu from '||quote_ident(tab)||' where seq = '||seq
	into cur_dest_rec;

    --  job for current dest
    execute 'select * from '||quote_ident(job_tab)||' where job = '||cur_dest_rec.job
	into cur_dest_job_rec;

    dist := cur_dest_rec.dist;
    load := cur_dest_rec.load_pcnt;
    while seq <> final_seqno 
	loop
	    -- find active link to next destination
	    execute 'select * from next_links('||quote_literal(link_tab)||','||seq||',''true'')'
		into next_links_rec;

	    -- fetch travel time/distance to next destination
	    execute 'select * from dest_time('||quote_literal(tab)||','||quote_literal(link_tab)||
		    ','||quote_literal(job_tab)
		    ||','||next_links_rec.next_dest||')'
		into td;
	    
	    -- calculate cumulative distance/time
	    dist := dist + td.dist;

	    -- compute timestamp to reach next destination
	    execute 'select '''||cur_dest_rec.time||'''::timestamp + '''||td.time||'''::interval as time'
		into next_dest_ts_rec;
	
	    -- path_dest row for next destination
	    execute 'select * from '||quote_ident(tab)||' where seq = '||next_links_rec.next_dest
		into next_dest_rec;

	    -- compute load at next dest

	    --  .. job for next dest
	    execute 'select * from '||quote_ident(job_tab)||' where job = '||next_dest_rec.job
		into next_dest_job_rec;  

	    if not cur_dest_rec.pu 
		then
		    -- if current dest is Drop, subtract load_pcnt 
		    load := load - cur_dest_job_rec.load_pcnt;
	    end if;
	    if next_dest_rec.pu
		then
		    -- if next dest is PU, add load_pcnt
		    load := load + next_dest_job_rec.load_pcnt;
	    end if;
		    

	    if  (-0.01 > (dist - next_dest_rec.dist) or ( dist - next_dest_rec.dist) > 0.01 ) or (next_dest_ts_rec.time != next_dest_rec.time) or ( -0.01 > (next_dest_rec.load_pcnt - load) or (next_dest_rec.load_pcnt - load) > 0.01 )
		then
		    -- we need to propagate down the path
		    change_cnt := change_cnt + 1; -- increment # of changes tally
		    -- apply the changes
		    execute 'update '||quote_ident(tab)||' set time = '''||next_dest_ts_rec.time||
			    '''::timestamp,dist = '||dist||',load_pcnt = '||load||' where seq = '||next_links_rec.next_dest ;

		    seq := next_links_rec.next_dest;
		    execute 'select time,dist,pu,job from '||quote_ident(tab)||' where seq = '||seq
			into cur_dest_rec;
		    --  job for next current dest
		    execute 'select * from '||quote_ident(job_tab)||' where job = '||cur_dest_rec.job
			into cur_dest_job_rec;
	    else
		-- no change, so halt the propagation
		return change_cnt;
	    end if;
	end loop;
   return change_cnt;
end;
$$
language 'plpgsql' volatile strict;


--
-- Find the set of destinations which precede another in the current path
--
create or replace function preceding_destinations(tab varchar,link_tab varchar, seq int)
    returns setof path_dest as 
$$
declare
    row1 record;
    row2 path_dest;
    sno int;
    row_cnt int;
begin
    sno := seq;
    if seq = 1
	then
	    return;
    end if;
    loop
	execute 'select * from prev_links('||quote_literal(link_tab)||','||sno||',''t'')'
	    into row1;
	get diagnostics row_cnt = ROW_COUNT;
	exit when row_cnt <= 0; -- this path segment must be detached !!
	-- follow the active links backwards until first node is reached
	execute 'select * from '||quote_ident(tab)||' where seq = ' ||row1.prev_dest
	    into row2;
	return next row2;
	exit when row2.seq = 1;
	sno := row1.prev_dest;
    end loop;
    return;
end;
$$
language 'plpgsql' volatile strict;
create or replace function preceding_destinations_inclusive(tab varchar,link_tab varchar,seq int)
    returns setof path_dest as
$$
declare
    row path_dest;
begin
    -- return the seq destination first
    execute 'select * from '||quote_ident(tab)||' where seq = '||seq
	into row;
    return next row;
    for row in execute 'select * from preceding_destinations('||quote_literal(tab)||','||
		    quote_literal(link_tab)||','||seq||')'
    loop
	return next row;
    end loop;
    return;

end;
$$
language 'plpgsql' volatile strict;



-- Find the set of destinations which follow another in the current path(inclusive)
--
create or replace function following_destinations(tab varchar,link_tab varchar, seq int)
    returns setof path_dest as 
$$
declare
    row1 record;
    row2 path_dest;
    sno int;
    max_seq int;
    row_cnt int;
begin
    -- find highest seq no in destinations set
    execute 'select max(seq) from '||quote_ident(tab)||' where job = 0'
	into max_seq;
    sno := seq;
    if seq = max_seq
	then
	    return;
    end if;
    loop
	execute 'select * from next_links('||quote_literal(link_tab)||','||sno||',''t'')'
	    into row1;
	get diagnostics row_cnt = ROW_COUNT;
	exit when row_cnt <= 0;  -- this part of the path must be detached !
	execute 'select * from '||quote_ident(tab)||' where seq = '||row1.next_dest
	    into row2;
	return next row2;
	exit when row2.seq = max_seq ;
	sno := row1.next_dest;
    end loop;
    return;
end;
$$
language 'plpgsql' volatile strict;

create or replace function following_destinations_inclusive(tab varchar,link_tab varchar,seq int)
    returns setof path_dest as
$$
declare
    row path_dest;
begin
    -- return the seq destination first
    execute 'select * from '||quote_ident(tab)||' where seq = '||seq
	into row;
    return next row;
    for row in execute 'select * from following_destinations('||quote_literal(tab)||','||
		    quote_literal(link_tab)||','||seq||')'
    loop
	return next row;
    end loop;
    return;

end;
$$
language 'plpgsql' volatile strict;



-- Find the set of destinations without predecessor in the current path (excluding first & last !)
--
create or replace function dests_without_pred(tab varchar,link_tab varchar)
    returns setof path_dest as 
$$
declare
    seq int;
    row path_dest;
begin
    for seq in execute 'select next_dest from '||quote_ident(link_tab)||' where not active except select next_dest from '||
	    quote_ident(link_tab)||' where active'

	loop
	    execute 'select * from '||quote_ident(tab)||' where seq = '||seq
		into row;
	    return next row;
    end loop;
    return;
end;
$$
language 'plpgsql' volatile strict;

-- Find the set of destinations without successor in the current path
--
create or replace function dests_without_succ(tab varchar,link_tab varchar)
    returns setof path_dest as 
$$
declare
    seq int;
    row path_dest;
begin
    for seq in execute 'select prev_dest from '||quote_ident(link_tab)||' where not active except select prev_dest from '||
	    quote_ident(link_tab)||' where active'

	loop
	    execute 'select * from '||quote_ident(tab)||' where seq = '||seq
		into row;
	    return next row;
    end loop;
    return;

end;
$$
language 'plpgsql' volatile strict;



-- 
-- 
-- Given an inconsistent load destination node, find the set of destinations where the
-- PU destinations precede it & the Drop destinations follow it.
-- ... returns the set of path_dest nodes
--
create or replace function pu_b4_drop_after(tab varchar,link_tab varchar,seq int)
    returns setof path_dest as
$$
declare
    row1 path_dest;
    dest path_dest;
begin
    for row1 in execute 'select * from preceding_destinations('||quote_literal(tab)||','||quote_literal(link_tab)||
		','||seq||')  where pu'
	loop
	    for dest in execute 'select * from following_destinations('||quote_literal(tab)||','||quote_literal(link_tab)||
		','||seq||') where not pu and job = '||row1.job
		loop
		    return next row1;
		    return next dest;
		    -- exit loop;  -- should only be one !!! .. unless multi-drops permitted
	    end loop;
    end loop;
    return;
end;
$$
language 'plpgsql' volatile strict;

--
-- Find the set of inconsistent destinations
--
create or replace function inconsistent_dests(tab varchar,link_tab varchar,max_dist float)
    returns setof inconsistent_path_dest_type as
$$
declare
    row1 record;
    row2 inconsistent_path_dest_type;
begin
    for row1 in execute 'select *,inconsistency_class('||quote_literal(tab)||','||
		quote_literal(link_tab)||',seq,'||max_dist||') as flag from '||quote_ident(tab)||
		'  where not consistent('||
		quote_literal(tab)||','||quote_literal(link_tab)||',seq,'||max_dist||') order by priority desc'
    loop
	row2.job := row1.job;
	row2.pu := row1.pu;
	row2.suburb := row1.suburb;
	row2.city := row1.city;
	row2.time := row1.time;
	row2.time_bound := row1.time_bound;
	row2.dist := row1.dist;
	row2.priority := row1.priority;
	row2.seq := row1.seq;
	row2.load_pcnt := row1.load_pcnt;
	row2.job_type := row1.job_type;
	row2.flag := row1.flag;
	return next row2;
    end loop;
    return;
end;
$$
language 'plpgsql' volatile strict;

--
-- Find the set of consistent destinations
--
create or replace function consistent_dests(tab varchar,link_tab varchar,max_dist float)
    returns setof path_dest as
$$
declare
    row1 path_dest;
begin
    for row1 in execute 'select * from '||quote_ident(tab)||' where consistent('||
		quote_literal(tab)||','||quote_literal(link_tab)||',seq,'||max_dist||') order by priority asc'
    loop
	return next row1;
    end loop;
    return;
end;
$$
language 'plpgsql' volatile strict;


--  DON'T USE THESE FUNCTIONS ANYMORE .... PRIORITY IS DIRECTLY RECORDED ON THE path_link RECORD
-- 	Priority of a path_link is the priority of the path_dest it is presently the predecessor of
-- if it is active.
-- 	If the link is inactive, its priority is negative of path_dest.
-- To activate an inactive link, the sum of its priority & the path_dest seeking it must exceed 0 !
--
create or replace function path_link_priority(tab varchar,link_tab varchar,prev_dest int,next_dest int)
    returns double precision as
$$
declare
    link path_links;
    dest path_dest;
begin
    execute 'select * from '||quote_ident(link_tab)||' where prev_dest = '||prev_dest||
		' and next_dest = '||next_dest
	into link;
    execute 'select * from '||quote_ident(tab)||' where seq = '||next_dest
	    into dest;
--    if dest.job == 0 or dest.pu is None:  # eg. this is an end-of-day job
--	return - dest.priority  # eg. end-of-day has no resistance priority
    if link.active != true
	then
	    return - dest.priority; -- eg. negative of the destinations existing priority 
    else
	return  dest.priority;
    end if;
end;
$$
language 'plpgsql' volatile strict;

create or replace function path_link_priority(tab varchar,next_dest int,active boolean)
    returns double precision as
$$
declare
    dest path_dest;
begin
    execute 'select * from '||quote_ident(tab)||' where seq = '||next_dest
	    into dest;
--    if dest.job == 0 or dest.pu is None:  # eg. this is an end-of-day job
--	return - dest.priority  # eg. end-of-day has no resistance priority
    if active != true
	then
	    return - dest.priority; -- eg. negative of the destinations existing priority 
    else
	return  dest.priority;
    end if;
end;
$$
language 'plpgsql' volatile strict;

-- 
-- This variant calculates the priority of moving a destination to a different position
-- in the active path.
-- .. prev_dest,next_dest = seq #'s of destinations between which to insert
--    dest = seq # of destination to be inserted 
create or replace function path_link_reloc_priority(tab varchar,link_tab varchar,prev_dest int,next_dest int,dest int)
    returns double precision as
$$
declare
    rec1 record;
    rec2 record;
    priority float(8);
    priority2 float(8);
    cnt int;
begin
    execute 'select count(*) from '||quote_ident(tab)||' a, '||quote_ident(tab)||
		' b where a.job = b.job and a.job_type not in (''p'',''P'',''e'',''E'')'
		||' and a.seq = '||prev_dest||' and b.seq = '||next_dest
	    into cnt;

    if cnt > 0
	then
	    -- NB. can omit this exit test iff no alternate path_links are created  for such jobs !!!
	    return 9e99; -- ie. cannot splice anything between PU/Drop of hourly job !!!
    end if;

    -- find the priority of the three active links which need to be deactivated (if active)
    execute 'select max(priority)  as priority,count(*) as count from path_link_deactivation_triple('||
		quote_literal(tab)||','||quote_literal(link_tab)||','||prev_dest|| ','||next_dest||','||dest||')'
	into rec1;
    execute 'select max(priority) as priority,count(*) as count from path_link_activation_triple('||
		quote_literal(tab)||','||quote_literal(link_tab)||','||prev_dest||','||next_dest||','||dest||')'
	into rec2;
    
    if rec1.count < 3
	then
	return 9e99;  -- ie. infinite priority
    else
	priority = rec1.priority;
    end if;
    if rec2.count < 3
	then
	return 9e99;  -- ie. infinite priority
    else
	priority2 = rec2.priority;
    end if;
--    return rec1.priority + rec2.priority;
    if priority2 > priority 
    then
	-- ie. the priority to activate an inactive link is the greater obstacle
	return priority2;
    else
	return priority;
    end if;
end;
$$
language 'plpgsql' volatile strict;
create or replace function path_link_reloc_priority(tab varchar,link_tab varchar,next_dest int,dest int)
    returns double precision as
$$
declare
    priority float(8);
    prev int;
begin
    -- find the priority of the three active links which need to be deactivated (if active)
    execute 'select prev_dest from path_links where active and next_dest = '||next_dest||' limit 1'
	into prev;

    execute 'select * from path_link_reloc_priority('||quote_literal(tab)||','
	|| quote_literal(link_tab)||','||prev|| ','||next_dest||','||dest||')'
	into priority;
    return priority;
end;
$$
language 'plpgsql' volatile strict;

-- This variant is for moving complete path segments bounded by two destinations to a new location
-- NB. this could replace the single destination version by simply feeding it the same destination twice !!! XXX
create or replace function path_link_reloc_priority_2(tab varchar,link_tab varchar,prev_dest int,next_dest int,dest int,dest2 int)
    returns double precision as
$$
declare
    rec1 record;
    rec2 record;
    priority float(8);
    priority2 float(8);
    cnt int;
begin
    execute 'select count(*) from '||quote_ident(tab)||' a, '||quote_ident(tab)||
		' b where a.job = b.job and a.job_type not in (''p'',''P'',''e'',''E'')'
		||' and a.seq = '||prev_dest||' and b.seq = '||next_dest
	    into cnt;

    if cnt > 0
	then
	    -- NB. can omit this exit test iff no alternate path_links are created  for such jobs !!!
	    return 9e99; -- ie. cannot splice anything between PU/Drop of hourly job !!!
    end if;

    -- find the priority of the three active links which need to be deactivated (if active)
    execute 'select max(priority)  as priority,count(*) as count from path_link_deactivation_triple('||
		quote_literal(tab)||','||quote_literal(link_tab)||','||prev_dest|| ','||next_dest||','||dest||
		','||dest2||')'
	into rec1;
    execute 'select max(priority) as priority,count(*) as count from path_link_activation_triple('||
		quote_literal(tab)||','||quote_literal(link_tab)||','||prev_dest||','||next_dest||','||dest||
		','||dest2||')'
	into rec2;
    
    if rec1.count < 3
	then
	return 9e99;  -- ie. infinite priority
    else
	priority = rec1.priority;
    end if;
    if rec2.count < 3
	then
	return 9e99;  -- ie. infinite priority
    else
	priority2 = rec2.priority;
    end if;
--    return rec1.priority + rec2.priority;
    if priority2 > priority 
    then
	-- ie. the priority to activate an inactive link is the greater obstacle
	return priority2;
    else
	return priority;
    end if;
end;
$$
language 'plpgsql' volatile strict;
create or replace function path_link_reloc_priority_2(tab varchar,link_tab varchar,next_dest int,dest int,dest2 int)
    returns double precision as
$$
declare
    priority float(8);
    prev int;
begin
    -- find the priority of the three active links which need to be deactivated (if active)
    execute 'select prev_dest from path_links where active and next_dest = '||next_dest||' limit 1'
	into prev;

    execute 'select * from path_link_reloc_priority_2('|| quote_literal(tab)||','||
	quote_literal(link_tab)||','||prev|| ','||next_dest||','||dest||
	','||dest2||')'
	into priority;
    return priority;
end;
$$
language 'plpgsql' volatile strict;



-- 
-- Find the pair of active path_links records which need to be deactivated to allow the specified
-- path_links record to be activated.
-- NB. this set may contain only one or even be empty !
--
create or replace function path_link_deactivation_pair(link_tab varchar,prev_dest int, next_dest int)
    returns setof path_links as
$$
declare
    link path_links;
begin
    for link in execute 'select * from '||quote_ident(link_tab)||' where  active and  ( prev_dest = '||prev_dest||
	    ' or next_dest = '||next_dest||')'
    loop
	return next link;
    end loop;
    return;
end;
$$
language 'plpgsql' volatile strict;

--
-- Find the three links which need to be deactivated 
-- to remove a destination from its current location & splice it in at a new
-- position in the active path indicated by the specified path_link.
-- 
-- dest = seq no of destination to be moved
-- prev_dest,next_dest = seq no's of destinations in-between which to insert dest
create or replace function path_link_deactivation_triple(tab varchar,link_tab varchar,prev_dest int,next_dest int,dest int)
    returns setof path_links as
$$
declare
    link path_links;
    rec1 record;
    rec2 record;
    row_count1 int;
    row_count2 int;
begin
    -- see if the job is hourly or p2p
    execute 'select * from '||quote_ident(tab)||' where seq = '||dest
	into rec1;
    get diagnostics row_count1 = ROW_COUNT;
    if row_count1 < 1
	then
	    return;
    end if;
    if rec1.job_type = 'p' or rec1.job_type  = 'P'
    then
    
	for link in execute 'select * from '||quote_ident(link_tab)||' where active and ( prev_dest = '||
		dest||' or next_dest = '||dest||' or ( prev_dest = '||prev_dest||' and next_dest = '||
		    next_dest||' ) )'
	loop
	    return next link;
	end loop;
    else 
	if rec1.job_type != 'f' and rec1.job_type != 'F' and rec1.job_type != 'h' and rec1.job_type != 'H'
	    then
		-- should not be called with any other job types
		return ;
	end if;
	-- the job is a hourly, so must keep link to PU/D
	-- .. fetch the other destination of the same job
	execute 'select * from '||quote_ident(tab)||' where job = '||rec1.job||' and not (seq = '||
		    dest||')'
	    into rec2;
	for link in execute 'select * from '||quote_ident(link_tab)||' where active and (prev_dest = '||
			prev_dest||' and next_dest = '||next_dest||')'
	loop
	
	    return next link;
	end loop;
	if rec2.pu = true
	then
	    -- dest is the drop, so need to get predecessor of rec2 & successor of rec1
	    for link in execute 'select * from '||quote_ident(link_tab)||' where active and  (next_dest = '||
			rec2.seq||')'
	    loop
		return next link;
	    end loop;
	    for link in execute 'select * from '||quote_ident(link_tab)||' where active and (prev_dest = '||
			rec1.seq||')'
	    loop
		return next link;
	    end loop;
	else
	    -- dest is the PU, so need to get predecessor or rec1 & successor rec2
	    -- dest is the drop, so need to get predecessor of rec2 & successor of rec1
	    for link in execute 'select * from '||quote_ident(link_tab)||' where active and  (next_dest = '||
			rec1.seq||')'
	    loop
		return next link;
	    end loop;
	    for link in execute 'select * from '||quote_ident(link_tab)||' where active and (prev_dest = '||
			rec2.seq||')'
	    loop
		return next link;
	    end loop;
	end if;
    end if;
    return;
end;
$$
language 'plpgsql' volatile strict;

-- Variant which accepts two destinations and computes change sets to shift the whole intermediate
-- path segment as a contiguous unit.
-- NB. this function should be called with destinations belonging to the same job (ie. PU & Drop)
-- ... also it is assumed dest precedes dest2 in the path
create or replace function path_link_deactivation_triple(tab varchar,link_tab varchar,prev_dest int,next_dest int,dest int, dest2 int)
    returns setof path_links as 
$$
declare
    link path_links;
    rec1 record;
    rec2 record;
    rec11 record;
    row_count11 int;
    row_count1 int;
    row_count2 int;
begin
    -- HERE XXX
    -- see if the job is hourly or p2p
    execute 'select * from '||quote_ident(tab)||' where seq = '||dest
	into rec1;
    get diagnostics row_count1 = ROW_COUNT;
    execute 'select * from '||quote_ident(tab)||' where seq = '||dest2
	into rec11;
    get diagnostics row_count11 = ROW_COUNT;
    if row_count1 < 1 or row_count11 < 1 or rec1.time > rec11.time
	then
	    return;
    end if;
    if rec1.job_type = 'e' or rec1.job_type = 'E' or rec11.job_type = 's' or rec11.job_type = 'S'
	then
	    -- dont shift start/end of day destinations
	    return;
    end if;

    if ( rec1.pu or (rec1.job_type = 'p' or  rec1.job_type = 'P' ))
	    and ( (not rec11.pu) or (rec11.job_type = 'p' or rec11.job_type = 'P'))
    then
	-- only accept non-p2p job destinations if dest is PU and dest2 is Drop
	for link in execute 'select * from '||quote_ident(link_tab)||' where active and ( next_dest = '||
		dest||' or prev_dest = '||dest2||' or ( prev_dest = '||prev_dest||' and next_dest = '||
		    next_dest||' ) )'
	loop
	    return next link;
	end loop;
    end if;
    return;
end;
$$
language 'plpgsql' volatile strict;

create or replace function path_link_deactivation_triple_oid(tab varchar,link_tab varchar,prev_dest int,next_dest int,dest  int)
    returns setof path_links_oid as
$$
declare
    link	path_links_oid;
    row1		record;
begin
    for row1 in execute 'select a.*,b.oid from path_link_deactivation_triple('||quote_literal(tab)||
		','||quote_literal(link_tab)||','||prev_dest||','||next_dest||','||dest||') a, '||
		quote_ident(link_tab)||' b where a.prev_dest = b.prev_dest and a.next_dest = b.next_dest'
    loop
	link.prev_dest := row1.prev_dest;
	link.next_dest := row1.next_dest;
	link.dist := row1.dist;
	link.time_int := row1.time_int;
	link.priority := row1.priority;
	link.active := row1.active;
	link.oid := row1.oid;
	return next link;
    end loop;
    return;
end;
$$
language 'plpgsql' volatile strict;

create or replace function path_link_deactivation_triple(tab varchar,link_tab varchar,next_dest int,dest int)
    returns setof path_links as
$$
declare
    link path_links;
    prev int;
begin
    execute 'select prev_dest from path_links where active and next_dest = '||next_dest||' limit 1'
	into prev;

    for link in execute 'select * from path_link_deactivation_triple('||
		quote_literal(tab)||','||quote_literal(link_tab)||','||prev||','||next_dest||','||dest||')'
    loop
	return next link;
    end loop;
    return;
end;
$$
language 'plpgsql' volatile strict;

-- As above, but gives the three path_links which need to be made active
-- NB. if this doesn't return three links , then the activation cannot be done !!!
--
create or replace function path_link_activation_triple(tab varchar,link_tab varchar,prev_dest int,next_dest int,dest int)
    returns setof path_links as
$$
declare
    link path_links;
    old_prev int;
    old_next int;
    rec1 record;
    rec2 record;
    rec4 record;
    rec5 record;
    row_count1 int;
    row_count2 int;
begin
    -- see if the job is hourly or p2p
    execute 'select * from '||quote_ident(tab)||' where seq = '||dest
	into rec1;

    if rec1.job_type = 'p' or rec1.job_type  = 'P'
    then
	-- the link which joins the original predecessor & succesor of dest together

	for link in execute 'select * from '||quote_ident(link_tab)||' where prev_dest in ( select prev_dest from '||
		quote_ident(link_tab)||' where active and next_dest = '||dest||
		') and next_dest in (select next_dest from '||quote_ident(link_tab)||
		' where active and prev_dest = '||dest||')'
	loop 
	    return next link;
	end loop;

	-- the two which splice dest into the new location
	for link in execute 'select * from '||quote_ident(link_tab)||' where ( prev_dest = '||
	    prev_dest||' and next_dest = '||dest||') or (prev_dest = '||dest||' and next_dest = '||
	    next_dest||') '
	loop
	    return next link;
	end loop;
    else
	-- the job is a hourly, so must keep link to PU/D
	-- .. fetch the other destination of the same job
	execute 'select * from '||quote_ident(tab)||' where job = '||rec1.job||' and not (seq = '||
		    dest||')'
	    into rec2;
	if rec2.pu = true
	then
	    -- dest is the drop, so need to get predecessor of rec2 & successor of rec1
	    for link in execute 'select * from '||quote_ident(link_tab)||' where next_dest = '||
			rec2.seq||' and prev_dest = '||prev_dest
	    loop
		return next link;
	    end loop;
	    for link in execute 'select * from '||quote_ident(link_tab)||' where active and prev_dest = '||
			rec1.seq||' and next_dest = '|| next_dest
	    loop
		return next link;
	    end loop;
	    -- now for the link which joins the original predecessor & successor of the hourly job together
	    execute 'select prev_dest from '||quote_ident(link_tab)||' where active and  next_dest = '||rec2.seq
		into old_prev;
	    get diagnostics row_count1 = ROW_COUNT;
	    execute 'select next_dest from '||quote_ident(link_tab)||' where active and  prev_dest = '||rec1.seq
		into old_next;
	    get diagnostics row_count1 = ROW_COUNT;
	    if row_count2 < 1 or row_count1 < 1
		then
		    return;
	    end if;
	    for link in execute 'select * from '||quote_ident(link_tab)||' where prev_dest = '||old_prev||
		' and next_dest = '||old_next||' limit 1'
	    loop
		return next link;
	    end loop;

	else
	    -- dest is the PU, so need to get predecessor or rec1 & successor rec2
	    for link in execute 'select * from '||quote_ident(link_tab)||' where next_dest = '||
			rec1.seq||' and prev_dest = '||prev_dest
	    loop
		return next link;
	    end loop;
	    for link in execute 'select * from '||quote_ident(link_tab)||' where active and prev_dest = '||
			rec2.seq||' and next_dest = '|| next_dest
	    loop
		return next link;
	    end loop;

	    -- now for the link which joins the original predecessor & successor of the hourly job together
	    for link in execute 'select * from '||quote_ident(link_tab)||' where prev_dest in ( select prev_dest from '||
		quote_ident(link_tab)||' where active and next_dest = '||rec1.seq||
		') and next_dest in (select next_dest from '||quote_ident(link_tab)||
		' where active and prev_dest = '||rec2.seq||')'
	    loop
		return next link;
	    end loop;

	end if;

    end if;
    return;
end;
$$
language 'plpgsql' volatile strict;


-- Variant takes two destinations representing a path segment to be moved as a contiguous unit.
-- NB. this function should be called with destinations belonging to the same job (ie. PU & Drop)
-- ... also it is assumed dest precedes dest2 in the path
create or replace function path_link_activation_triple(tab varchar,link_tab varchar,prev_dest int,next_dest int,dest int,dest2 int)
    returns setof path_links as
$$
declare
    link path_links;
    old_prev int;
    old_next int;
    rec1 record;
    rec2 record;
    rec4 record;
    rec5 record;
    rec11 record;
    row_count1 int;
    row_count2 int;
    row_count11 int;
begin
    -- see if the job is hourly or p2p
    execute 'select * from '||quote_ident(tab)||' where seq = '||dest
	into rec1;
    get diagnostics row_count1 = ROW_COUNT;
    execute 'select * from '||quote_ident(tab)||' where seq = '||dest2
	into rec11;
    get diagnostics row_count11 = ROW_COUNT;
    if row_count1 < 1 or row_count11 < 1 or rec1.time > rec11.time
	then
	    return;
    end if;
    if rec1.job_type = 'e' or rec1.job_type = 'E' or rec11.job_type = 's' or rec11.job_type = 'S'
	then
	    -- dont shift start/end of day destinations
	    return;
    end if;
    
    if ( rec1.pu or (rec1.job_type = 'p' or  rec1.job_type = 'P' ))
	    and ( (not rec11.pu) or (rec11.job_type = 'p' or rec11.job_type = 'P'))
    then
	-- only accept non-p2p job destinations if dest is PU and dest2 is Drop

	-- the link which joins the original predecessor & successor of dest together
	for link in execute 'select * from '||quote_ident(link_tab)||' where prev_dest in ( select prev_dest from '||
		quote_ident(link_tab)||' where active and next_dest = '||dest||
		') and next_dest in (select next_dest from '||quote_ident(link_tab)||
		' where active and prev_dest = '||dest2||')'
	loop 
	    return next link;
	end loop;

	-- the two which splice dest into the new location
	for link in execute 'select * from '||quote_ident(link_tab)||' where ( prev_dest = '||
	    prev_dest||' and next_dest = '||dest||') or (prev_dest = '||dest2||' and next_dest = '||
	    next_dest||') '
	loop
	    return next link;
	end loop;
      end if;
    return;
end;
$$
language 'plpgsql' volatile strict;

create or replace function path_link_activation_triple_oid(tab varchar,link_tab varchar,prev_dest int,next_dest int,dest  int)
    returns setof path_links_oid as
$$
declare
    link	path_links_oid;
    row1	record;
begin
    for row1 in execute 'select a.*,b.oid from path_link_activation_triple('||quote_literal(tab)||
		','||quote_literal(link_tab)||','||prev_dest||','||next_dest||','||dest||') a, '||
		quote_ident(link_tab)||' b where a.prev_dest = b.prev_dest and a.next_dest = b.next_dest'
    loop
	link.prev_dest := row1.prev_dest;
	link.next_dest := row1.next_dest;
	link.dist := row1.dist;
	link.time_int := row1.time_int;
	link.priority := row1.priority;
	link.active := row1.active;
	link.oid := row1.oid;
	return next link;
    end loop;
    return;
end;
$$
language 'plpgsql' volatile strict;

create or replace function path_link_activation_triple(tab varchar,link_tab varchar,next_dest int,dest int)
    returns setof path_links as
$$
declare
    link path_links;
    prev int;
begin
    execute 'select prev_dest from path_links where active and next_dest = '||next_dest||' limit 1'
	into prev;

    for link in execute 'select * from path_link_activation_triple('||
		quote_literal(tab)||','||quote_literal(link_tab)||','||prev||','||next_dest||','||dest||')'
    loop
	return next link;
    end loop;
    return;
end;
$$
language 'plpgsql' volatile strict;

