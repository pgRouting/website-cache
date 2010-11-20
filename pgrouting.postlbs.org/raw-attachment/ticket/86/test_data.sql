--
-- PostgreSQL database dump
--

SET client_encoding = 'LATIN1';
SET standard_conforming_strings = off;
SET check_function_bodies = false;
SET client_min_messages = warning;
SET escape_string_warning = off;

SET search_path = public, pg_catalog;

SET default_tablespace = '';

SET default_with_oids = true;

--
-- Name: path_dest; Type: TABLE; Schema: public; Owner: transport; Tablespace: 
--

CREATE TABLE path_dest (
    job integer,
    pu boolean,
    suburb character varying,
    city character varying,
    "time" timestamp without time zone,
    time_bound timestamp without time zone,
    dist real,
    priority double precision,
    seq integer NOT NULL,
    job_type character(1),
    load_pcnt real
);


ALTER TABLE public.path_dest OWNER TO transport;

--
-- Name: path_links; Type: TABLE; Schema: public; Owner: transport; Tablespace: 
--

CREATE TABLE path_links (
    prev_dest integer NOT NULL,
    next_dest integer NOT NULL,
    dist real,
    time_int interval,
    active boolean,
    priority double precision
);


ALTER TABLE public.path_links OWNER TO transport;

--
-- Name: debug_table; Type: TABLE; Schema: public; Owner: transport; Tablespace: 
--

CREATE TABLE debug_table (
    msg character varying,
    number bigint
);


ALTER TABLE public.debug_table OWNER TO transport;

--
-- Name: path_job; Type: TABLE; Schema: public; Owner: transport; Tablespace: 
--

CREATE TABLE path_job (
    job integer NOT NULL,
    load_pcnt real,
    direct_dist real,
    priority double precision,
    time_int interval,
    job_type character varying(1)
);


ALTER TABLE public.path_job OWNER TO transport;

--
-- Data for Name: debug_table; Type: TABLE DATA; Schema: public; Owner: transport
--

INSERT INTO debug_table (msg, number) VALUES ('^^^ Dist too long: number of option_costs = 14', 2);
INSERT INTO debug_table (msg, number) VALUES ('--- In Move wout Gridlock, Chosen IS option prev=4,next=5,dest=3,priority=6.0,cost=5.0,non_dist inconsistencies=2, inconsistencies=2.57692,total_dist=150.0,inconsistent_priority=13.461538434', 4);
INSERT INTO debug_table (msg, number) VALUES ('^^^ Dist too long: number of option_costs = 16', 5);
INSERT INTO debug_table (msg, number) VALUES ('--- In Move wout Gridlock, Chosen IS option prev=3,next=5,dest=11,priority=6.0,cost=5.0,non_dist inconsistencies=3, inconsistencies=3.57308,total_dist=149.0,inconsistent_priority=16.4384614229', 7);
INSERT INTO debug_table (msg, number) VALUES ('^^^ Dist too long: number of option_costs = 18', 8);
INSERT INTO debug_table (msg, number) VALUES ('--- In Move wout Gridlock, Chosen IS option prev=2,next=4,dest=10,priority=6.0,cost=5.0,non_dist inconsistencies=3, inconsistencies=3.0,total_dist=125.0,inconsistent_priority=13.0', 10);
INSERT INTO debug_table (msg, number) VALUES ('Vehicle overloaded, prev=5,next=6,dest=3,priority=5.0, detect = 4', 11);
INSERT INTO debug_table (msg, number) VALUES (' *** Re-apply best gridlock escape found!!! : best dist = 131.0,time=03:40:00,inconcist=4.50385,consist=3,inconsist pr=19.0230770111,consist pr=9.0, best option = 3  ', 12);
INSERT INTO debug_table (msg, number) VALUES ('Gridlock: update path_links set priority = 6.000000 where prev/dest in (4/11,3/6,5/3)', 13);
INSERT INTO debug_table (msg, number) VALUES ('update path_links set priority = 5.000000 where ( prev_dest = 3 and next_dest = 11) or (prev_dest = 4 and next_dest = 3) or (prev_dest = 5 and next_dest = 6)', 14);
INSERT INTO debug_table (msg, number) VALUES ('** Gridlock: Increased priority of seq=3 to 5.000000', 15);
INSERT INTO debug_table (msg, number) VALUES ('^^^ Dist too long: number of option_costs = 18', 16);
INSERT INTO debug_table (msg, number) VALUES ('--- In Move wout Gridlock, Chosen IS option prev=10,next=4,dest=3,priority=6.0,cost=5.0,non_dist inconsistencies=2, inconsistencies=2.0,total_dist=130.0,inconsistent_priority=9.0', 18);
INSERT INTO debug_table (msg, number) VALUES ('Vehicle overloaded, prev=11,next=5,dest=4,priority=6.0, detect = 4', 19);
INSERT INTO debug_table (msg, number) VALUES ('--- In Move wout Gridlock, Chosen IS option prev=11,next=5,dest=4,priority=6.0,cost=4.0,non_dist inconsistencies=0, inconsistencies=0.515385,total_dist=134.0,inconsistent_priority=3.09230768681', 20);
INSERT INTO debug_table (msg, number) VALUES ('^^^ Dist too long: number of option_costs = 14', 21);
INSERT INTO debug_table (msg, number) VALUES (' *** Re-apply best gridlock escape found!!! : best dist = 124.0,time=03:10:00,inconcist=0.0,consist=8,inconsist pr=0.0,consist pr=32.0, best option = 11  ', 23);
INSERT INTO debug_table (msg, number) VALUES ('Gridlock: update path_links set priority = 7.000000 where prev/dest in (3/4,10/11,11/3)', 24);
INSERT INTO debug_table (msg, number) VALUES ('update path_links set priority = 6.000000 where ( prev_dest = 3 and next_dest = 11) or (prev_dest = 10 and next_dest = 3) or (prev_dest = 11 and next_dest = 4)', 25);
INSERT INTO debug_table (msg, number) VALUES ('** Gridlock: Increased priority of seq=11 to 6.000000', 26);
INSERT INTO debug_table (msg, number) VALUES (' ### END of prog, cum exec times: mainloop=00:01:19.370798 apply_changes=00:00:17.319982 ,gridlock_time=00:00:16.520317,non_gridlock_time=00:00:00.000988', 27);


--
-- Data for Name: path_dest; Type: TABLE DATA; Schema: public; Owner: transport
--

INSERT INTO path_dest (job, pu, suburb, city, "time", time_bound, dist, priority, seq, job_type, load_pcnt) VALUES (2, true, 'beenleigh', 'brisbane', '2009-02-01 08:30:00', '2009-02-01 08:30:00', 25, 3, 2, 'p', 0.40000001);
INSERT INTO path_dest (job, pu, suburb, city, "time", time_bound, dist, priority, seq, job_type, load_pcnt) VALUES (5, true, 'springwood', 'brisbane', '2009-02-01 08:45:00', '2009-02-01 08:00:00', 35, 3, 10, 'p', 1);
INSERT INTO path_dest (job, pu, suburb, city, "time", time_bound, dist, priority, seq, job_type, load_pcnt) VALUES (5, false, 'murarrie', 'brisbane', '2009-02-01 09:05:00', '2009-02-01 14:00:00', 55, 3, 11, 'p', 1);
INSERT INTO path_dest (job, pu, suburb, city, "time", time_bound, dist, priority, seq, job_type, load_pcnt) VALUES (2, false, 'murarrie', 'brisbane', '2009-02-01 09:15:00', '2009-02-01 10:00:00', 65, 5, 3, 'p', 0.40000001);
INSERT INTO path_dest (job, pu, suburb, city, "time", time_bound, dist, priority, seq, job_type, load_pcnt) VALUES (4, true, 'lytton', 'brisbane', '2009-02-01 09:25:00', '2009-02-01 09:00:00', 70, 6, 4, 'p', 0.69999999);
INSERT INTO path_dest (job, pu, suburb, city, "time", time_bound, dist, priority, seq, job_type, load_pcnt) VALUES (4, false, 'rocklea', 'brisbane', '2009-02-01 10:10:00', '2009-02-01 12:00:00', 89, 3, 5, 'p', 0.69999999);
INSERT INTO path_dest (job, pu, suburb, city, "time", time_bound, dist, priority, seq, job_type, load_pcnt) VALUES (0, NULL, 'redland bay', 'brisbane', '2009-02-01 18:00:00', '2009-02-01 18:00:00', 124, 7, 6, 'e', -5.9604599e-08);
INSERT INTO path_dest (job, pu, suburb, city, "time", time_bound, dist, priority, seq, job_type, load_pcnt) VALUES (0, NULL, 'redland bay', 'brisbane', '2009-02-01 08:00:00', '2009-02-01 08:00:00', 0, 3, 1, 's', 0);


--
-- Data for Name: path_job; Type: TABLE DATA; Schema: public; Owner: transport
--

INSERT INTO path_job (job, load_pcnt, direct_dist, priority, time_int, job_type) VALUES (2, 0.40000001, 20, 1, '00:30:00', 'p');
INSERT INTO path_job (job, load_pcnt, direct_dist, priority, time_int, job_type) VALUES (4, 0.69999999, 25, 1, '00:45:00', 'p');
INSERT INTO path_job (job, load_pcnt, direct_dist, priority, time_int, job_type) VALUES (5, 0.60000002, 20, 1, '00:30:00', 'p');


--
-- Data for Name: path_links; Type: TABLE DATA; Schema: public; Owner: transport
--

INSERT INTO path_links (prev_dest, next_dest, dist, time_int, active, priority) VALUES (11, 10, 20, '00:20:00', false, 2);
INSERT INTO path_links (prev_dest, next_dest, dist, time_int, active, priority) VALUES (2, 6, 18, '00:25:00', false, 2);
INSERT INTO path_links (prev_dest, next_dest, dist, time_int, active, priority) VALUES (10, 6, 15, '00:20:00', false, 2);
INSERT INTO path_links (prev_dest, next_dest, dist, time_int, active, priority) VALUES (1, 5, 34, '00:41:00', false, 2);
INSERT INTO path_links (prev_dest, next_dest, dist, time_int, active, priority) VALUES (4, 6, 39, '00:35:00', false, 2);
INSERT INTO path_links (prev_dest, next_dest, dist, time_int, active, priority) VALUES (5, 4, 19, '00:24:00', false, 2);
INSERT INTO path_links (prev_dest, next_dest, dist, time_int, active, priority) VALUES (1, 11, 40, '00:55:00', false, 3);
INSERT INTO path_links (prev_dest, next_dest, dist, time_int, active, priority) VALUES (1, 3, 32, '00:40:00', false, 3);
INSERT INTO path_links (prev_dest, next_dest, dist, time_int, active, priority) VALUES (3, 2, 18, '00:35:00', false, 2);
INSERT INTO path_links (prev_dest, next_dest, dist, time_int, active, priority) VALUES (2, 11, 24, '00:27:00', false, 4);
INSERT INTO path_links (prev_dest, next_dest, dist, time_int, active, priority) VALUES (4, 2, 23, '00:25:00', false, 4);
INSERT INTO path_links (prev_dest, next_dest, dist, time_int, active, priority) VALUES (2, 5, 18, '00:22:00', false, 2);
INSERT INTO path_links (prev_dest, next_dest, dist, time_int, active, priority) VALUES (11, 2, 20, '00:25:00', false, 2);
INSERT INTO path_links (prev_dest, next_dest, dist, time_int, active, priority) VALUES (5, 10, 30, '00:50:00', false, 5);
INSERT INTO path_links (prev_dest, next_dest, dist, time_int, active, priority) VALUES (10, 5, 30, '00:45:00', false, 2);
INSERT INTO path_links (prev_dest, next_dest, dist, time_int, active, priority) VALUES (5, 2, 28, '00:30:00', false, 5);
INSERT INTO path_links (prev_dest, next_dest, dist, time_int, active, priority) VALUES (11, 6, 35, '00:55:00', false, 4);
INSERT INTO path_links (prev_dest, next_dest, dist, time_int, active, priority) VALUES (3, 11, 10, '00:19:00', false, 6);
INSERT INTO path_links (prev_dest, next_dest, dist, time_int, active, priority) VALUES (3, 10, 15, '00:25:00', false, 5);
INSERT INTO path_links (prev_dest, next_dest, dist, time_int, active, priority) VALUES (2, 3, 20, '00:40:00', false, 6);
INSERT INTO path_links (prev_dest, next_dest, dist, time_int, active, priority) VALUES (3, 5, 21, '00:50:00', false, 6);
INSERT INTO path_links (prev_dest, next_dest, dist, time_int, active, priority) VALUES (10, 2, 15, '00:20:00', false, 3);
INSERT INTO path_links (prev_dest, next_dest, dist, time_int, active, priority) VALUES (1, 10, 30, '00:35:00', false, 6);
INSERT INTO path_links (prev_dest, next_dest, dist, time_int, active, priority) VALUES (3, 6, 27, '00:45:00', false, 5);
INSERT INTO path_links (prev_dest, next_dest, dist, time_int, active, priority) VALUES (5, 3, 19, '00:45:00', false, 6);
INSERT INTO path_links (prev_dest, next_dest, dist, time_int, active, priority) VALUES (5, 11, 25, '00:40:00', false, 4);
INSERT INTO path_links (prev_dest, next_dest, dist, time_int, active, priority) VALUES (5, 6, 35, '01:00:00', true, 4);
INSERT INTO path_links (prev_dest, next_dest, dist, time_int, active, priority) VALUES (1, 4, 29, '00:55:00', false, 5);
INSERT INTO path_links (prev_dest, next_dest, dist, time_int, active, priority) VALUES (1, 2, 25, '00:30:00', true, 4);
INSERT INTO path_links (prev_dest, next_dest, dist, time_int, active, priority) VALUES (4, 10, 15, '00:15:00', false, 2);
INSERT INTO path_links (prev_dest, next_dest, dist, time_int, active, priority) VALUES (2, 4, 24, '00:30:00', false, 4);
INSERT INTO path_links (prev_dest, next_dest, dist, time_int, active, priority) VALUES (2, 10, 10, '00:15:00', true, 4);
INSERT INTO path_links (prev_dest, next_dest, dist, time_int, active, priority) VALUES (4, 3, 5, '00:10:00', false, 4);
INSERT INTO path_links (prev_dest, next_dest, dist, time_int, active, priority) VALUES (10, 4, 10, '00:25:00', false, 5);
INSERT INTO path_links (prev_dest, next_dest, dist, time_int, active, priority) VALUES (11, 5, 30, '00:45:00', false, 6);
INSERT INTO path_links (prev_dest, next_dest, dist, time_int, active, priority) VALUES (4, 11, 10, '00:15:00', false, 2);
INSERT INTO path_links (prev_dest, next_dest, dist, time_int, active, priority) VALUES (4, 5, 19, '00:45:00', true, 3);
INSERT INTO path_links (prev_dest, next_dest, dist, time_int, active, priority) VALUES (11, 4, 20, '00:15:00', false, 5);
INSERT INTO path_links (prev_dest, next_dest, dist, time_int, active, priority) VALUES (3, 4, 5, '00:10:00', true, 3);
INSERT INTO path_links (prev_dest, next_dest, dist, time_int, active, priority) VALUES (10, 11, 20, '00:20:00', true, 6);
INSERT INTO path_links (prev_dest, next_dest, dist, time_int, active, priority) VALUES (11, 3, 10, '00:10:00', true, 6);
INSERT INTO path_links (prev_dest, next_dest, dist, time_int, active, priority) VALUES (10, 3, 15, '00:20:00', false, 7);


--
-- Name: path_job_pkey; Type: CONSTRAINT; Schema: public; Owner: transport; Tablespace: 
--

ALTER TABLE ONLY path_job
    ADD CONSTRAINT path_job_pkey PRIMARY KEY (job);


--
-- Name: path_links_pkey; Type: CONSTRAINT; Schema: public; Owner: transport; Tablespace: 
--

ALTER TABLE ONLY path_links
    ADD CONSTRAINT path_links_pkey PRIMARY KEY (prev_dest, next_dest);


--
-- Name: path_tab_pkey; Type: CONSTRAINT; Schema: public; Owner: transport; Tablespace: 
--

ALTER TABLE ONLY path_dest
    ADD CONSTRAINT path_tab_pkey PRIMARY KEY (seq);


--
-- Name: path_jindx; Type: INDEX; Schema: public; Owner: transport; Tablespace: 
--

CREATE INDEX path_jindx ON path_dest USING btree (job);


--
-- PostgreSQL database dump complete
--

