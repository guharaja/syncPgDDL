/*****************************************************************************
	see README.md for complete setup instructions. read README first!
	Else, modify the following variables, run file in psql in the target db
*****************************************************************************/
\set dbname 'test_db'	
\set user 'postgres'
\set sqls 'C:\\Users\\postgres\\Documents\\sqls'
\set prog 'C:\\tools\\PostgreSQL.9.5\\bin\\pg_dump.exe'
/*****************************************************************************/

\! chcp 1252
\set ON_ERROR_STOP

--\set pass '''set PGPASSWORD=':password'\n'
-- \set errs 'C:\\Users\\postgres\\Documents\\sqls'
\set conn ' --host=localhost --port=5432 --username=':user' --no-password '
\set othrs ' --format=plain --schema-only --serializable-deferrable '
\set file '--file="':sqls'\\':dbname'.schema.sql"'
\set dump '"':prog'" --dbname=':dbname :conn :othrs :file
--\set cmd '':pass:dump''
\set cmd '''':dump''''
\echo
\echo complete pg_dump command: :cmd

-- pg_dump -dpostgres -Upostgres -w -FP --schema-only -C --clean -fC:/Users/postgres/Documents/sqls/postgres.schema.sql"
-- pg_dump -dtest_db -Upostgres -w -FP --schema-only -C --clean -fC:/Users/postgres/Documents/sqls/test_db.schema.sql

\set origdb :DBNAME
--------------------------------------------------------
\echo
\connect postgres
SET client_min_messages TO WARNING;
\echo 'Creating schema dumper in ':DBNAME' . . .'

TRUNCATE TABLE pgagent.pga_job CASCADE;
TRUNCATE TABLE pgagent.pga_joblog CASCADE;
TRUNCATE TABLE pgagent.pga_jobstep CASCADE;
TRUNCATE TABLE pgagent.pga_jobsteplog CASCADE;

ALTER SEQUENCE pgagent.pga_job_jobid_seq RESTART WITH 1;
ALTER SEQUENCE pgagent.pga_joblog_jlgid_seq RESTART WITH 1;
ALTER SEQUENCE pgagent.pga_jobstep_jstid_seq RESTART WITH 1;
ALTER SEQUENCE pgagent.pga_jobsteplog_jslid_seq RESTART WITH 1;

INSERT INTO pgagent.pga_job (jobid, jobjclid, jobenabled, jobhostagent, jobname,       jobdesc) 
					VALUES	(1,     1,        true,       'rlan',       'pg_dump_job', '' );
INSERT INTO pgagent.pga_jobstep 
	(jstid, jstjobid, jstenabled, jstkind, jstonerror, jstcode, jstname,        jstdbname, jstdesc, jstconnstr) VALUES  
	(1,     1,        true,       'b',     'f',        :cmd ,   'pg_dump_step', '',        '',      '');

SET client_min_messages TO NOTICE;
--------------------------------------------------------

\echo
\connect :dbname
SET client_min_messages TO WARNING;
\echo 'Creating schema dumper in ' :dbname ' . . .'

DROP EVENT TRIGGER IF EXISTS etrg_ddl_was_run CASCADE;
DROP FUNCTION IF EXISTS sched_pg_dump_run() CASCADE;
DROP EXTENSION IF EXISTS dblink;

CREATE EXTENSION IF NOT EXISTS dblink;

-- GRANT EXECUTE on FUNCTION public.dblink_connect_u( TEXT, TEXT ) TO postgres;

CREATE OR REPLACE FUNCTION sched_pg_dump_run()
		RETURNS event_trigger AS $$
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
$$ LANGUAGE plpgsql;

CREATE EVENT TRIGGER etrg_ddl_was_run 
		ON ddl_command_end 
		EXECUTE PROCEDURE sched_pg_dump_run();

SET client_min_messages TO NOTICE;
\unset ON_ERROR_STOP
\connect :origdb
-----------------------------------------------------------
