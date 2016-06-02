--
-- PostgreSQL database dump
--

-- Dumped from database version 9.5.3
-- Dumped by pg_dump version 9.5.3

SET statement_timeout = 0;
SET lock_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SET check_function_bodies = false;
SET client_min_messages = warning;
SET row_security = off;

DROP DATABASE test_db;
--
-- Name: test_db; Type: DATABASE; Schema: -; Owner: postgres
--

CREATE DATABASE test_db WITH TEMPLATE = template0 ENCODING = 'UTF8' LC_COLLATE = 'English_United States.1252' LC_CTYPE = 'English_United States.1252';


ALTER DATABASE test_db OWNER TO postgres;

\connect test_db

SET statement_timeout = 0;
SET lock_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SET check_function_bodies = false;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: public; Type: SCHEMA; Schema: -; Owner: postgres
--

CREATE SCHEMA public;


ALTER SCHEMA public OWNER TO postgres;

--
-- Name: SCHEMA public; Type: COMMENT; Schema: -; Owner: postgres
--

COMMENT ON SCHEMA public IS 'standard public schema';


--
-- Name: plpgsql; Type: EXTENSION; Schema: -; Owner: 
--

CREATE EXTENSION IF NOT EXISTS plpgsql WITH SCHEMA pg_catalog;


--
-- Name: EXTENSION plpgsql; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION plpgsql IS 'PL/pgSQL procedural language';


--
-- Name: dblink; Type: EXTENSION; Schema: -; Owner: 
--

CREATE EXTENSION IF NOT EXISTS dblink WITH SCHEMA public;


--
-- Name: EXTENSION dblink; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION dblink IS 'connect to other PostgreSQL databases from within a database';


SET search_path = public, pg_catalog;

--
-- Name: sched_pg_dump_run(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION sched_pg_dump_run() RETURNS event_trigger
    LANGUAGE plpgsql
    AS $$
	DECLARE	
		pass 		TEXT := 'postgres';
		updt 		TEXT;
		link 		TEXT;
		retVal 		TEXT;
	BEGIN
		updt := 'UPDATE pgagent.pga_job SET jobnextrun = NOW() + ''20 sec''::INTERVAL 
					WHERE jobname = ''pg_dump_job'';'; --  AND jobid = 1;';
		link := 'dbname=postgres user=postgres password=' || pass; 
		-- link := 'dbname=postgres user=postgres'; 
		BEGIN
			--SELECT dblink_connect_u( 'pg_link'::TEXT, link::TEXT ) INTO STRICT retVal;
			SELECT dblink_connect( 'pg_link'::TEXT, link::TEXT ) INTO STRICT retVal;
			SELECT dblink_exec( 'pg_link'::TEXT, updt::TEXT, true::BOOL ) INTO STRICT retVal;
		EXCEPTION WHEN others THEN	
			--SELECT dblink_cancel_query( 'pg_link'::TEXT ) INTO STRICT retVal;
			RAISE EXCEPTION 'dblink_exec: 
					user: ''%''
					sql:''%''
					link:''%''
					retVal:''%''
					sqlstate:''%''
					message:''%''
				', USER, updt, link, retval, SQLSTATE, SQLERRM;
		END;
		SELECT dblink_disconnect( 'pg_link'::TEXT ) INTO STRICT retVal;
	END; 
$$;


ALTER FUNCTION public.sched_pg_dump_run() OWNER TO postgres;

SET default_tablespace = '';

SET default_with_oids = false;

--
-- Name: test; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE test (
    id integer NOT NULL,
    a integer
);


ALTER TABLE test OWNER TO postgres;

--
-- Name: test_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE test_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE test_id_seq OWNER TO postgres;

--
-- Name: test_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE test_id_seq OWNED BY test.id;


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY test ALTER COLUMN id SET DEFAULT nextval('test_id_seq'::regclass);


--
-- Name: etrg_ddl_was_run; Type: EVENT TRIGGER; Schema: -; Owner: postgres
--

CREATE EVENT TRIGGER etrg_ddl_was_run ON ddl_command_end
   EXECUTE PROCEDURE public.sched_pg_dump_run();


--
-- Name: public; Type: ACL; Schema: -; Owner: postgres
--

REVOKE ALL ON SCHEMA public FROM PUBLIC;
REVOKE ALL ON SCHEMA public FROM postgres;
GRANT ALL ON SCHEMA public TO postgres;
GRANT ALL ON SCHEMA public TO PUBLIC;


--
-- PostgreSQL database dump complete
--

