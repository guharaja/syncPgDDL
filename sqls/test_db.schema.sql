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

--
-- Name: postgres; Type: COMMENT; Schema: -; Owner: postgres
--

COMMENT ON DATABASE postgres IS 'default administrative connection database';


--
-- Name: pgagent; Type: SCHEMA; Schema: -; Owner: postgres
--

CREATE SCHEMA pgagent;


ALTER SCHEMA pgagent OWNER TO postgres;

--
-- Name: SCHEMA pgagent; Type: COMMENT; Schema: -; Owner: postgres
--

COMMENT ON SCHEMA pgagent IS 'pgAgent system tables';


--
-- Name: plpgsql; Type: EXTENSION; Schema: -; Owner: 
--

CREATE EXTENSION IF NOT EXISTS plpgsql WITH SCHEMA pg_catalog;


--
-- Name: EXTENSION plpgsql; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION plpgsql IS 'PL/pgSQL procedural language';


--
-- Name: adminpack; Type: EXTENSION; Schema: -; Owner: 
--

CREATE EXTENSION IF NOT EXISTS adminpack WITH SCHEMA pg_catalog;


--
-- Name: EXTENSION adminpack; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION adminpack IS 'administrative functions for PostgreSQL';


SET search_path = pgagent, pg_catalog;

--
-- Name: pga_exception_trigger(); Type: FUNCTION; Schema: pgagent; Owner: postgres
--

CREATE FUNCTION pga_exception_trigger() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE

    v_jobid int4 := 0;

BEGIN

     IF TG_OP = 'DELETE' THEN

        SELECT INTO v_jobid jscjobid FROM pgagent.pga_schedule WHERE jscid = OLD.jexscid;

        -- update pga_job from remaining schedules
        -- the actual calculation of jobnextrun will be performed in the trigger
        UPDATE pgagent.pga_job
           SET jobnextrun = NULL
         WHERE jobenabled AND jobid = v_jobid;
        RETURN OLD;
    ELSE

        SELECT INTO v_jobid jscjobid FROM pgagent.pga_schedule WHERE jscid = NEW.jexscid;

        UPDATE pgagent.pga_job
           SET jobnextrun = NULL
         WHERE jobenabled AND jobid = v_jobid;
        RETURN NEW;
    END IF;
END;
$$;


ALTER FUNCTION pgagent.pga_exception_trigger() OWNER TO postgres;

--
-- Name: FUNCTION pga_exception_trigger(); Type: COMMENT; Schema: pgagent; Owner: postgres
--

COMMENT ON FUNCTION pga_exception_trigger() IS 'Update the job''s next run time whenever an exception changes';


--
-- Name: pga_is_leap_year(smallint); Type: FUNCTION; Schema: pgagent; Owner: postgres
--

CREATE FUNCTION pga_is_leap_year(smallint) RETURNS boolean
    LANGUAGE plpgsql IMMUTABLE
    AS $_$
BEGIN
    IF $1 % 4 != 0 THEN
        RETURN FALSE;
    END IF;

    IF $1 % 100 != 0 THEN
        RETURN TRUE;
    END IF;

    RETURN $1 % 400 = 0;
END;
$_$;


ALTER FUNCTION pgagent.pga_is_leap_year(smallint) OWNER TO postgres;

--
-- Name: FUNCTION pga_is_leap_year(smallint); Type: COMMENT; Schema: pgagent; Owner: postgres
--

COMMENT ON FUNCTION pga_is_leap_year(smallint) IS 'Returns TRUE if $1 is a leap year';


--
-- Name: pga_job_trigger(); Type: FUNCTION; Schema: pgagent; Owner: postgres
--

CREATE FUNCTION pga_job_trigger() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF NEW.jobenabled THEN
        IF NEW.jobnextrun IS NULL THEN
             SELECT INTO NEW.jobnextrun
                    MIN(pgagent.pga_next_schedule(jscid, jscstart, jscend, jscminutes, jschours, jscweekdays, jscmonthdays, jscmonths))
               FROM pgagent.pga_schedule
              WHERE jscenabled AND jscjobid=OLD.jobid;
        END IF;
    ELSE
        NEW.jobnextrun := NULL;
    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION pgagent.pga_job_trigger() OWNER TO postgres;

--
-- Name: FUNCTION pga_job_trigger(); Type: COMMENT; Schema: pgagent; Owner: postgres
--

COMMENT ON FUNCTION pga_job_trigger() IS 'Update the job''s next run time.';


--
-- Name: pga_next_schedule(integer, timestamp with time zone, timestamp with time zone, boolean[], boolean[], boolean[], boolean[], boolean[]); Type: FUNCTION; Schema: pgagent; Owner: postgres
--

CREATE FUNCTION pga_next_schedule(integer, timestamp with time zone, timestamp with time zone, boolean[], boolean[], boolean[], boolean[], boolean[]) RETURNS timestamp with time zone
    LANGUAGE plpgsql
    AS $_$
DECLARE
    jscid           ALIAS FOR $1;
    jscstart        ALIAS FOR $2;
    jscend          ALIAS FOR $3;
    jscminutes      ALIAS FOR $4;
    jschours        ALIAS FOR $5;
    jscweekdays     ALIAS FOR $6;
    jscmonthdays    ALIAS FOR $7;
    jscmonths       ALIAS FOR $8;

    nextrun         timestamp := '1970-01-01 00:00:00-00';
    runafter        timestamp := '1970-01-01 00:00:00-00';

    bingo            bool := FALSE;
    gotit            bool := FALSE;
    foundval        bool := FALSE;
    daytweak        bool := FALSE;
    minutetweak        bool := FALSE;

    i                int2 := 0;
    d                int2 := 0;

    nextminute        int2 := 0;
    nexthour        int2 := 0;
    nextday            int2 := 0;
    nextmonth       int2 := 0;
    nextyear        int2 := 0;


BEGIN
    -- No valid start date has been specified
    IF jscstart IS NULL THEN RETURN NULL; END IF;

    -- The schedule is past its end date
    IF jscend IS NOT NULL AND jscend < now() THEN RETURN NULL; END IF;

    -- Get the time to find the next run after. It will just be the later of
    -- now() + 1m and the start date for the time being, however, we might want to
    -- do more complex things using this value in the future.
    IF date_trunc('MINUTE', jscstart) > date_trunc('MINUTE', (now() + '1 Minute'::interval)) THEN
        runafter := date_trunc('MINUTE', jscstart);
    ELSE
        runafter := date_trunc('MINUTE', (now() + '1 Minute'::interval));
    END IF;

    --
    -- Enter a loop, generating next run timestamps until we find one
    -- that falls on the required weekday, and is not matched by an exception
    --

    WHILE bingo = FALSE LOOP

        --
        -- Get the next run year
        --
        nextyear := date_part('YEAR', runafter);

        --
        -- Get the next run month
        --
        nextmonth := date_part('MONTH', runafter);
        gotit := FALSE;
        FOR i IN (nextmonth) .. 12 LOOP
            IF jscmonths[i] = TRUE THEN
                nextmonth := i;
                gotit := TRUE;
                foundval := TRUE;
                EXIT;
            END IF;
        END LOOP;
        IF gotit = FALSE THEN
            FOR i IN 1 .. (nextmonth - 1) LOOP
                IF jscmonths[i] = TRUE THEN
                    nextmonth := i;

                    -- Wrap into next year
                    nextyear := nextyear + 1;
                    gotit := TRUE;
                    foundval := TRUE;
                    EXIT;
                END IF;
           END LOOP;
        END IF;

        --
        -- Get the next run day
        --
        -- If the year, or month have incremented, get the lowest day,
        -- otherwise look for the next day matching or after today.
        IF (nextyear > date_part('YEAR', runafter) OR nextmonth > date_part('MONTH', runafter)) THEN
            nextday := 1;
            FOR i IN 1 .. 32 LOOP
                IF jscmonthdays[i] = TRUE THEN
                    nextday := i;
                    foundval := TRUE;
                    EXIT;
                END IF;
            END LOOP;
        ELSE
            nextday := date_part('DAY', runafter);
            gotit := FALSE;
            FOR i IN nextday .. 32 LOOP
                IF jscmonthdays[i] = TRUE THEN
                    nextday := i;
                    gotit := TRUE;
                    foundval := TRUE;
                    EXIT;
                END IF;
            END LOOP;
            IF gotit = FALSE THEN
                FOR i IN 1 .. (nextday - 1) LOOP
                    IF jscmonthdays[i] = TRUE THEN
                        nextday := i;

                        -- Wrap into next month
                        IF nextmonth = 12 THEN
                            nextyear := nextyear + 1;
                            nextmonth := 1;
                        ELSE
                            nextmonth := nextmonth + 1;
                        END IF;
                        gotit := TRUE;
                        foundval := TRUE;
                        EXIT;
                    END IF;
                END LOOP;
            END IF;
        END IF;

        -- Was the last day flag selected?
        IF nextday = 32 THEN
            IF nextmonth = 1 THEN
                nextday := 31;
            ELSIF nextmonth = 2 THEN
                IF pgagent.pga_is_leap_year(nextyear) = TRUE THEN
                    nextday := 29;
                ELSE
                    nextday := 28;
                END IF;
            ELSIF nextmonth = 3 THEN
                nextday := 31;
            ELSIF nextmonth = 4 THEN
                nextday := 30;
            ELSIF nextmonth = 5 THEN
                nextday := 31;
            ELSIF nextmonth = 6 THEN
                nextday := 30;
            ELSIF nextmonth = 7 THEN
                nextday := 31;
            ELSIF nextmonth = 8 THEN
                nextday := 31;
            ELSIF nextmonth = 9 THEN
                nextday := 30;
            ELSIF nextmonth = 10 THEN
                nextday := 31;
            ELSIF nextmonth = 11 THEN
                nextday := 30;
            ELSIF nextmonth = 12 THEN
                nextday := 31;
            END IF;
        END IF;

        --
        -- Get the next run hour
        --
        -- If the year, month or day have incremented, get the lowest hour,
        -- otherwise look for the next hour matching or after the current one.
        IF (nextyear > date_part('YEAR', runafter) OR nextmonth > date_part('MONTH', runafter) OR nextday > date_part('DAY', runafter) OR daytweak = TRUE) THEN
            nexthour := 0;
            FOR i IN 1 .. 24 LOOP
                IF jschours[i] = TRUE THEN
                    nexthour := i - 1;
                    foundval := TRUE;
                    EXIT;
                END IF;
            END LOOP;
        ELSE
            nexthour := date_part('HOUR', runafter);
            gotit := FALSE;
            FOR i IN (nexthour + 1) .. 24 LOOP
                IF jschours[i] = TRUE THEN
                    nexthour := i - 1;
                    gotit := TRUE;
                    foundval := TRUE;
                    EXIT;
                END IF;
            END LOOP;
            IF gotit = FALSE THEN
                FOR i IN 1 .. nexthour LOOP
                    IF jschours[i] = TRUE THEN
                        nexthour := i - 1;

                        -- Wrap into next month
                        IF (nextmonth = 1 OR nextmonth = 3 OR nextmonth = 5 OR nextmonth = 7 OR nextmonth = 8 OR nextmonth = 10 OR nextmonth = 12) THEN
                            d = 31;
                        ELSIF (nextmonth = 4 OR nextmonth = 6 OR nextmonth = 9 OR nextmonth = 11) THEN
                            d = 30;
                        ELSE
                            IF pgagent.pga_is_leap_year(nextyear) = TRUE THEN
                                d := 29;
                            ELSE
                                d := 28;
                            END IF;
                        END IF;

                        IF nextday = d THEN
                            nextday := 1;
                            IF nextmonth = 12 THEN
                                nextyear := nextyear + 1;
                                nextmonth := 1;
                            ELSE
                                nextmonth := nextmonth + 1;
                            END IF;
                        ELSE
                            nextday := nextday + 1;
                        END IF;

                        gotit := TRUE;
                        foundval := TRUE;
                        EXIT;
                    END IF;
                END LOOP;
            END IF;
        END IF;

        --
        -- Get the next run minute
        --
        -- If the year, month day or hour have incremented, get the lowest minute,
        -- otherwise look for the next minute matching or after the current one.
        IF (nextyear > date_part('YEAR', runafter) OR nextmonth > date_part('MONTH', runafter) OR nextday > date_part('DAY', runafter) OR nexthour > date_part('HOUR', runafter) OR daytweak = TRUE) THEN
            nextminute := 0;
            IF minutetweak = TRUE THEN
        d := 1;
            ELSE
        d := date_part('YEAR', runafter)::int2;
            END IF;
            FOR i IN d .. 60 LOOP
                IF jscminutes[i] = TRUE THEN
                    nextminute := i - 1;
                    foundval := TRUE;
                    EXIT;
                END IF;
            END LOOP;
        ELSE
            nextminute := date_part('MINUTE', runafter);
            gotit := FALSE;
            FOR i IN (nextminute + 1) .. 60 LOOP
                IF jscminutes[i] = TRUE THEN
                    nextminute := i - 1;
                    gotit := TRUE;
                    foundval := TRUE;
                    EXIT;
                END IF;
            END LOOP;
            IF gotit = FALSE THEN
                FOR i IN 1 .. nextminute LOOP
                    IF jscminutes[i] = TRUE THEN
                        nextminute := i - 1;

                        -- Wrap into next hour
                        IF (nextmonth = 1 OR nextmonth = 3 OR nextmonth = 5 OR nextmonth = 7 OR nextmonth = 8 OR nextmonth = 10 OR nextmonth = 12) THEN
                            d = 31;
                        ELSIF (nextmonth = 4 OR nextmonth = 6 OR nextmonth = 9 OR nextmonth = 11) THEN
                            d = 30;
                        ELSE
                            IF pgagent.pga_is_leap_year(nextyear) = TRUE THEN
                                d := 29;
                            ELSE
                                d := 28;
                            END IF;
                        END IF;

                        IF nexthour = 23 THEN
                            nexthour = 0;
                            IF nextday = d THEN
                                nextday := 1;
                                IF nextmonth = 12 THEN
                                    nextyear := nextyear + 1;
                                    nextmonth := 1;
                                ELSE
                                    nextmonth := nextmonth + 1;
                                END IF;
                            ELSE
                                nextday := nextday + 1;
                            END IF;
                        ELSE
                            nexthour := nexthour + 1;
                        END IF;

                        gotit := TRUE;
                        foundval := TRUE;
                        EXIT;
                    END IF;
                END LOOP;
            END IF;
        END IF;

        -- Build the result, and check it is not the same as runafter - this may
        -- happen if all array entries are set to false. In this case, add a minute.

        nextrun := (nextyear::varchar || '-'::varchar || nextmonth::varchar || '-' || nextday::varchar || ' ' || nexthour::varchar || ':' || nextminute::varchar)::timestamptz;

        IF nextrun = runafter AND foundval = FALSE THEN
                nextrun := nextrun + INTERVAL '1 Minute';
        END IF;

        -- If the result is past the end date, exit.
        IF nextrun > jscend THEN
            RETURN NULL;
        END IF;

        -- Check to ensure that the nextrun time is actually still valid. Its
        -- possible that wrapped values may have carried the nextrun onto an
        -- invalid time or date.
        IF ((jscminutes = '{f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}' OR jscminutes[date_part('MINUTE', nextrun) + 1] = TRUE) AND
            (jschours = '{f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}' OR jschours[date_part('HOUR', nextrun) + 1] = TRUE) AND
            (jscmonthdays = '{f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}' OR jscmonthdays[date_part('DAY', nextrun)] = TRUE OR
            (jscmonthdays = '{f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,t}' AND
             ((date_part('MONTH', nextrun) IN (1,3,5,7,8,10,12) AND date_part('DAY', nextrun) = 31) OR
              (date_part('MONTH', nextrun) IN (4,6,9,11) AND date_part('DAY', nextrun) = 30) OR
              (date_part('MONTH', nextrun) = 2 AND ((pgagent.pga_is_leap_year(date_part('DAY', nextrun)::int2) AND date_part('DAY', nextrun) = 29) OR date_part('DAY', nextrun) = 28))))) AND
            (jscmonths = '{f,f,f,f,f,f,f,f,f,f,f,f}' OR jscmonths[date_part('MONTH', nextrun)] = TRUE)) THEN


            -- Now, check to see if the nextrun time found is a) on an acceptable
            -- weekday, and b) not matched by an exception. If not, set
            -- runafter = nextrun and try again.

            -- Check for a wildcard weekday
            gotit := FALSE;
            FOR i IN 1 .. 7 LOOP
                IF jscweekdays[i] = TRUE THEN
                    gotit := TRUE;
                    EXIT;
                END IF;
            END LOOP;

            -- OK, is the correct weekday selected, or a wildcard?
            IF (jscweekdays[date_part('DOW', nextrun) + 1] = TRUE OR gotit = FALSE) THEN

                -- Check for exceptions
                SELECT INTO d jexid FROM pgagent.pga_exception WHERE jexscid = jscid AND ((jexdate = nextrun::date AND jextime = nextrun::time) OR (jexdate = nextrun::date AND jextime IS NULL) OR (jexdate IS NULL AND jextime = nextrun::time));
                IF FOUND THEN
                    -- Nuts - found an exception. Increment the time and try again
                    runafter := nextrun + INTERVAL '1 Minute';
                    bingo := FALSE;
                    minutetweak := TRUE;
            daytweak := FALSE;
                ELSE
                    bingo := TRUE;
                END IF;
            ELSE
                -- We're on the wrong week day - increment a day and try again.
                runafter := nextrun + INTERVAL '1 Day';
                bingo := FALSE;
                minutetweak := FALSE;
                daytweak := TRUE;
            END IF;

        ELSE
            runafter := nextrun + INTERVAL '1 Minute';
            bingo := FALSE;
            minutetweak := TRUE;
        daytweak := FALSE;
        END IF;

    END LOOP;

    RETURN nextrun;
END;
$_$;


ALTER FUNCTION pgagent.pga_next_schedule(integer, timestamp with time zone, timestamp with time zone, boolean[], boolean[], boolean[], boolean[], boolean[]) OWNER TO postgres;

--
-- Name: FUNCTION pga_next_schedule(integer, timestamp with time zone, timestamp with time zone, boolean[], boolean[], boolean[], boolean[], boolean[]); Type: COMMENT; Schema: pgagent; Owner: postgres
--

COMMENT ON FUNCTION pga_next_schedule(integer, timestamp with time zone, timestamp with time zone, boolean[], boolean[], boolean[], boolean[], boolean[]) IS 'Calculates the next runtime for a given schedule';


--
-- Name: pga_schedule_trigger(); Type: FUNCTION; Schema: pgagent; Owner: postgres
--

CREATE FUNCTION pga_schedule_trigger() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        -- update pga_job from remaining schedules
        -- the actual calculation of jobnextrun will be performed in the trigger
        UPDATE pgagent.pga_job
           SET jobnextrun = NULL
         WHERE jobenabled AND jobid=OLD.jscjobid;
        RETURN OLD;
    ELSE
        UPDATE pgagent.pga_job
           SET jobnextrun = NULL
         WHERE jobenabled AND jobid=NEW.jscjobid;
        RETURN NEW;
    END IF;
END;
$$;


ALTER FUNCTION pgagent.pga_schedule_trigger() OWNER TO postgres;

--
-- Name: FUNCTION pga_schedule_trigger(); Type: COMMENT; Schema: pgagent; Owner: postgres
--

COMMENT ON FUNCTION pga_schedule_trigger() IS 'Update the job''s next run time whenever a schedule changes';


--
-- Name: pgagent_schema_version(); Type: FUNCTION; Schema: pgagent; Owner: postgres
--

CREATE FUNCTION pgagent_schema_version() RETURNS smallint
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- RETURNS PGAGENT MAJOR VERSION
    -- WE WILL CHANGE THE MAJOR VERSION, ONLY IF THERE IS A SCHEMA CHANGE
    RETURN 3;
END;
$$;


ALTER FUNCTION pgagent.pgagent_schema_version() OWNER TO postgres;

SET default_tablespace = '';

SET default_with_oids = false;

--
-- Name: pga_exception; Type: TABLE; Schema: pgagent; Owner: postgres
--

CREATE TABLE pga_exception (
    jexid integer NOT NULL,
    jexscid integer NOT NULL,
    jexdate date,
    jextime time without time zone
);


ALTER TABLE pga_exception OWNER TO postgres;

--
-- Name: pga_exception_jexid_seq; Type: SEQUENCE; Schema: pgagent; Owner: postgres
--

CREATE SEQUENCE pga_exception_jexid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE pga_exception_jexid_seq OWNER TO postgres;

--
-- Name: pga_exception_jexid_seq; Type: SEQUENCE OWNED BY; Schema: pgagent; Owner: postgres
--

ALTER SEQUENCE pga_exception_jexid_seq OWNED BY pga_exception.jexid;


--
-- Name: pga_job; Type: TABLE; Schema: pgagent; Owner: postgres
--

CREATE TABLE pga_job (
    jobid integer NOT NULL,
    jobjclid integer NOT NULL,
    jobname text NOT NULL,
    jobdesc text DEFAULT ''::text NOT NULL,
    jobhostagent text DEFAULT ''::text NOT NULL,
    jobenabled boolean DEFAULT true NOT NULL,
    jobcreated timestamp with time zone DEFAULT now() NOT NULL,
    jobchanged timestamp with time zone DEFAULT now() NOT NULL,
    jobagentid integer,
    jobnextrun timestamp with time zone,
    joblastrun timestamp with time zone
);


ALTER TABLE pga_job OWNER TO postgres;

--
-- Name: TABLE pga_job; Type: COMMENT; Schema: pgagent; Owner: postgres
--

COMMENT ON TABLE pga_job IS 'Job main entry';


--
-- Name: COLUMN pga_job.jobagentid; Type: COMMENT; Schema: pgagent; Owner: postgres
--

COMMENT ON COLUMN pga_job.jobagentid IS 'Agent that currently executes this job.';


--
-- Name: pga_job_jobid_seq; Type: SEQUENCE; Schema: pgagent; Owner: postgres
--

CREATE SEQUENCE pga_job_jobid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE pga_job_jobid_seq OWNER TO postgres;

--
-- Name: pga_job_jobid_seq; Type: SEQUENCE OWNED BY; Schema: pgagent; Owner: postgres
--

ALTER SEQUENCE pga_job_jobid_seq OWNED BY pga_job.jobid;


--
-- Name: pga_jobagent; Type: TABLE; Schema: pgagent; Owner: postgres
--

CREATE TABLE pga_jobagent (
    jagpid integer NOT NULL,
    jaglogintime timestamp with time zone DEFAULT now() NOT NULL,
    jagstation text NOT NULL
);


ALTER TABLE pga_jobagent OWNER TO postgres;

--
-- Name: TABLE pga_jobagent; Type: COMMENT; Schema: pgagent; Owner: postgres
--

COMMENT ON TABLE pga_jobagent IS 'Active job agents';


--
-- Name: pga_jobclass; Type: TABLE; Schema: pgagent; Owner: postgres
--

CREATE TABLE pga_jobclass (
    jclid integer NOT NULL,
    jclname text NOT NULL
);


ALTER TABLE pga_jobclass OWNER TO postgres;

--
-- Name: TABLE pga_jobclass; Type: COMMENT; Schema: pgagent; Owner: postgres
--

COMMENT ON TABLE pga_jobclass IS 'Job classification';


--
-- Name: pga_jobclass_jclid_seq; Type: SEQUENCE; Schema: pgagent; Owner: postgres
--

CREATE SEQUENCE pga_jobclass_jclid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE pga_jobclass_jclid_seq OWNER TO postgres;

--
-- Name: pga_jobclass_jclid_seq; Type: SEQUENCE OWNED BY; Schema: pgagent; Owner: postgres
--

ALTER SEQUENCE pga_jobclass_jclid_seq OWNED BY pga_jobclass.jclid;


--
-- Name: pga_joblog; Type: TABLE; Schema: pgagent; Owner: postgres
--

CREATE TABLE pga_joblog (
    jlgid integer NOT NULL,
    jlgjobid integer NOT NULL,
    jlgstatus character(1) DEFAULT 'r'::bpchar NOT NULL,
    jlgstart timestamp with time zone DEFAULT now() NOT NULL,
    jlgduration interval,
    CONSTRAINT pga_joblog_jlgstatus_check CHECK ((jlgstatus = ANY (ARRAY['r'::bpchar, 's'::bpchar, 'f'::bpchar, 'i'::bpchar, 'd'::bpchar])))
);


ALTER TABLE pga_joblog OWNER TO postgres;

--
-- Name: TABLE pga_joblog; Type: COMMENT; Schema: pgagent; Owner: postgres
--

COMMENT ON TABLE pga_joblog IS 'Job run logs.';


--
-- Name: COLUMN pga_joblog.jlgstatus; Type: COMMENT; Schema: pgagent; Owner: postgres
--

COMMENT ON COLUMN pga_joblog.jlgstatus IS 'Status of job: r=running, s=successfully finished, f=failed, i=no steps to execute, d=aborted';


--
-- Name: pga_joblog_jlgid_seq; Type: SEQUENCE; Schema: pgagent; Owner: postgres
--

CREATE SEQUENCE pga_joblog_jlgid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE pga_joblog_jlgid_seq OWNER TO postgres;

--
-- Name: pga_joblog_jlgid_seq; Type: SEQUENCE OWNED BY; Schema: pgagent; Owner: postgres
--

ALTER SEQUENCE pga_joblog_jlgid_seq OWNED BY pga_joblog.jlgid;


--
-- Name: pga_jobstep; Type: TABLE; Schema: pgagent; Owner: postgres
--

CREATE TABLE pga_jobstep (
    jstid integer NOT NULL,
    jstjobid integer NOT NULL,
    jstname text NOT NULL,
    jstdesc text DEFAULT ''::text NOT NULL,
    jstenabled boolean DEFAULT true NOT NULL,
    jstkind character(1) NOT NULL,
    jstcode text NOT NULL,
    jstconnstr text DEFAULT ''::text NOT NULL,
    jstdbname name DEFAULT ''::name NOT NULL,
    jstonerror character(1) DEFAULT 'f'::bpchar NOT NULL,
    jscnextrun timestamp with time zone,
    CONSTRAINT pga_jobstep_check CHECK ((((jstconnstr <> ''::text) AND (jstkind = 's'::bpchar)) OR ((jstconnstr = ''::text) AND ((jstkind = 'b'::bpchar) OR (jstdbname <> ''::name))))),
    CONSTRAINT pga_jobstep_check1 CHECK ((((jstdbname <> ''::name) AND (jstkind = 's'::bpchar)) OR ((jstdbname = ''::name) AND ((jstkind = 'b'::bpchar) OR (jstconnstr <> ''::text))))),
    CONSTRAINT pga_jobstep_jstkind_check CHECK ((jstkind = ANY (ARRAY['b'::bpchar, 's'::bpchar]))),
    CONSTRAINT pga_jobstep_jstonerror_check CHECK ((jstonerror = ANY (ARRAY['f'::bpchar, 's'::bpchar, 'i'::bpchar])))
);


ALTER TABLE pga_jobstep OWNER TO postgres;

--
-- Name: TABLE pga_jobstep; Type: COMMENT; Schema: pgagent; Owner: postgres
--

COMMENT ON TABLE pga_jobstep IS 'Job step to be executed';


--
-- Name: COLUMN pga_jobstep.jstkind; Type: COMMENT; Schema: pgagent; Owner: postgres
--

COMMENT ON COLUMN pga_jobstep.jstkind IS 'Kind of jobstep: s=sql, b=batch';


--
-- Name: COLUMN pga_jobstep.jstonerror; Type: COMMENT; Schema: pgagent; Owner: postgres
--

COMMENT ON COLUMN pga_jobstep.jstonerror IS 'What to do if step returns an error: f=fail the job, s=mark step as succeeded and continue, i=mark as fail but ignore it and proceed';


--
-- Name: pga_jobstep_jstid_seq; Type: SEQUENCE; Schema: pgagent; Owner: postgres
--

CREATE SEQUENCE pga_jobstep_jstid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE pga_jobstep_jstid_seq OWNER TO postgres;

--
-- Name: pga_jobstep_jstid_seq; Type: SEQUENCE OWNED BY; Schema: pgagent; Owner: postgres
--

ALTER SEQUENCE pga_jobstep_jstid_seq OWNED BY pga_jobstep.jstid;


--
-- Name: pga_jobsteplog; Type: TABLE; Schema: pgagent; Owner: postgres
--

CREATE TABLE pga_jobsteplog (
    jslid integer NOT NULL,
    jsljlgid integer NOT NULL,
    jsljstid integer NOT NULL,
    jslstatus character(1) DEFAULT 'r'::bpchar NOT NULL,
    jslresult integer,
    jslstart timestamp with time zone DEFAULT now() NOT NULL,
    jslduration interval,
    jsloutput text,
    CONSTRAINT pga_jobsteplog_jslstatus_check CHECK ((jslstatus = ANY (ARRAY['r'::bpchar, 's'::bpchar, 'i'::bpchar, 'f'::bpchar, 'd'::bpchar])))
);


ALTER TABLE pga_jobsteplog OWNER TO postgres;

--
-- Name: TABLE pga_jobsteplog; Type: COMMENT; Schema: pgagent; Owner: postgres
--

COMMENT ON TABLE pga_jobsteplog IS 'Job step run logs.';


--
-- Name: COLUMN pga_jobsteplog.jslstatus; Type: COMMENT; Schema: pgagent; Owner: postgres
--

COMMENT ON COLUMN pga_jobsteplog.jslstatus IS 'Status of job step: r=running, s=successfully finished,  f=failed stopping job, i=ignored failure, d=aborted';


--
-- Name: COLUMN pga_jobsteplog.jslresult; Type: COMMENT; Schema: pgagent; Owner: postgres
--

COMMENT ON COLUMN pga_jobsteplog.jslresult IS 'Return code of job step';


--
-- Name: pga_jobsteplog_jslid_seq; Type: SEQUENCE; Schema: pgagent; Owner: postgres
--

CREATE SEQUENCE pga_jobsteplog_jslid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE pga_jobsteplog_jslid_seq OWNER TO postgres;

--
-- Name: pga_jobsteplog_jslid_seq; Type: SEQUENCE OWNED BY; Schema: pgagent; Owner: postgres
--

ALTER SEQUENCE pga_jobsteplog_jslid_seq OWNED BY pga_jobsteplog.jslid;


--
-- Name: pga_schedule; Type: TABLE; Schema: pgagent; Owner: postgres
--

CREATE TABLE pga_schedule (
    jscid integer NOT NULL,
    jscjobid integer NOT NULL,
    jscname text NOT NULL,
    jscdesc text DEFAULT ''::text NOT NULL,
    jscenabled boolean DEFAULT true NOT NULL,
    jscstart timestamp with time zone DEFAULT now() NOT NULL,
    jscend timestamp with time zone,
    jscminutes boolean[] DEFAULT '{f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}'::boolean[] NOT NULL,
    jschours boolean[] DEFAULT '{f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}'::boolean[] NOT NULL,
    jscweekdays boolean[] DEFAULT '{f,f,f,f,f,f,f}'::boolean[] NOT NULL,
    jscmonthdays boolean[] DEFAULT '{f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}'::boolean[] NOT NULL,
    jscmonths boolean[] DEFAULT '{f,f,f,f,f,f,f,f,f,f,f,f}'::boolean[] NOT NULL,
    CONSTRAINT pga_schedule_jschours_size CHECK ((array_upper(jschours, 1) = 24)),
    CONSTRAINT pga_schedule_jscminutes_size CHECK ((array_upper(jscminutes, 1) = 60)),
    CONSTRAINT pga_schedule_jscmonthdays_size CHECK ((array_upper(jscmonthdays, 1) = 32)),
    CONSTRAINT pga_schedule_jscmonths_size CHECK ((array_upper(jscmonths, 1) = 12)),
    CONSTRAINT pga_schedule_jscweekdays_size CHECK ((array_upper(jscweekdays, 1) = 7))
);


ALTER TABLE pga_schedule OWNER TO postgres;

--
-- Name: TABLE pga_schedule; Type: COMMENT; Schema: pgagent; Owner: postgres
--

COMMENT ON TABLE pga_schedule IS 'Job schedule exceptions';


--
-- Name: pga_schedule_jscid_seq; Type: SEQUENCE; Schema: pgagent; Owner: postgres
--

CREATE SEQUENCE pga_schedule_jscid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE pga_schedule_jscid_seq OWNER TO postgres;

--
-- Name: pga_schedule_jscid_seq; Type: SEQUENCE OWNED BY; Schema: pgagent; Owner: postgres
--

ALTER SEQUENCE pga_schedule_jscid_seq OWNED BY pga_schedule.jscid;


--
-- Name: jexid; Type: DEFAULT; Schema: pgagent; Owner: postgres
--

ALTER TABLE ONLY pga_exception ALTER COLUMN jexid SET DEFAULT nextval('pga_exception_jexid_seq'::regclass);


--
-- Name: jobid; Type: DEFAULT; Schema: pgagent; Owner: postgres
--

ALTER TABLE ONLY pga_job ALTER COLUMN jobid SET DEFAULT nextval('pga_job_jobid_seq'::regclass);


--
-- Name: jclid; Type: DEFAULT; Schema: pgagent; Owner: postgres
--

ALTER TABLE ONLY pga_jobclass ALTER COLUMN jclid SET DEFAULT nextval('pga_jobclass_jclid_seq'::regclass);


--
-- Name: jlgid; Type: DEFAULT; Schema: pgagent; Owner: postgres
--

ALTER TABLE ONLY pga_joblog ALTER COLUMN jlgid SET DEFAULT nextval('pga_joblog_jlgid_seq'::regclass);


--
-- Name: jstid; Type: DEFAULT; Schema: pgagent; Owner: postgres
--

ALTER TABLE ONLY pga_jobstep ALTER COLUMN jstid SET DEFAULT nextval('pga_jobstep_jstid_seq'::regclass);


--
-- Name: jslid; Type: DEFAULT; Schema: pgagent; Owner: postgres
--

ALTER TABLE ONLY pga_jobsteplog ALTER COLUMN jslid SET DEFAULT nextval('pga_jobsteplog_jslid_seq'::regclass);


--
-- Name: jscid; Type: DEFAULT; Schema: pgagent; Owner: postgres
--

ALTER TABLE ONLY pga_schedule ALTER COLUMN jscid SET DEFAULT nextval('pga_schedule_jscid_seq'::regclass);


--
-- Name: pga_exception_pkey; Type: CONSTRAINT; Schema: pgagent; Owner: postgres
--

ALTER TABLE ONLY pga_exception
    ADD CONSTRAINT pga_exception_pkey PRIMARY KEY (jexid);


--
-- Name: pga_job_pkey; Type: CONSTRAINT; Schema: pgagent; Owner: postgres
--

ALTER TABLE ONLY pga_job
    ADD CONSTRAINT pga_job_pkey PRIMARY KEY (jobid);


--
-- Name: pga_jobagent_pkey; Type: CONSTRAINT; Schema: pgagent; Owner: postgres
--

ALTER TABLE ONLY pga_jobagent
    ADD CONSTRAINT pga_jobagent_pkey PRIMARY KEY (jagpid);


--
-- Name: pga_jobclass_pkey; Type: CONSTRAINT; Schema: pgagent; Owner: postgres
--

ALTER TABLE ONLY pga_jobclass
    ADD CONSTRAINT pga_jobclass_pkey PRIMARY KEY (jclid);


--
-- Name: pga_joblog_pkey; Type: CONSTRAINT; Schema: pgagent; Owner: postgres
--

ALTER TABLE ONLY pga_joblog
    ADD CONSTRAINT pga_joblog_pkey PRIMARY KEY (jlgid);


--
-- Name: pga_jobstep_pkey; Type: CONSTRAINT; Schema: pgagent; Owner: postgres
--

ALTER TABLE ONLY pga_jobstep
    ADD CONSTRAINT pga_jobstep_pkey PRIMARY KEY (jstid);


--
-- Name: pga_jobsteplog_pkey; Type: CONSTRAINT; Schema: pgagent; Owner: postgres
--

ALTER TABLE ONLY pga_jobsteplog
    ADD CONSTRAINT pga_jobsteplog_pkey PRIMARY KEY (jslid);


--
-- Name: pga_schedule_pkey; Type: CONSTRAINT; Schema: pgagent; Owner: postgres
--

ALTER TABLE ONLY pga_schedule
    ADD CONSTRAINT pga_schedule_pkey PRIMARY KEY (jscid);


--
-- Name: pga_exception_datetime; Type: INDEX; Schema: pgagent; Owner: postgres
--

CREATE UNIQUE INDEX pga_exception_datetime ON pga_exception USING btree (jexdate, jextime);


--
-- Name: pga_exception_jexscid; Type: INDEX; Schema: pgagent; Owner: postgres
--

CREATE INDEX pga_exception_jexscid ON pga_exception USING btree (jexscid);


--
-- Name: pga_jobclass_name; Type: INDEX; Schema: pgagent; Owner: postgres
--

CREATE UNIQUE INDEX pga_jobclass_name ON pga_jobclass USING btree (jclname);


--
-- Name: pga_joblog_jobid; Type: INDEX; Schema: pgagent; Owner: postgres
--

CREATE INDEX pga_joblog_jobid ON pga_joblog USING btree (jlgjobid);


--
-- Name: pga_jobschedule_jobid; Type: INDEX; Schema: pgagent; Owner: postgres
--

CREATE INDEX pga_jobschedule_jobid ON pga_schedule USING btree (jscjobid);


--
-- Name: pga_jobstep_jobid; Type: INDEX; Schema: pgagent; Owner: postgres
--

CREATE INDEX pga_jobstep_jobid ON pga_jobstep USING btree (jstjobid);


--
-- Name: pga_jobsteplog_jslid; Type: INDEX; Schema: pgagent; Owner: postgres
--

CREATE INDEX pga_jobsteplog_jslid ON pga_jobsteplog USING btree (jsljlgid);


--
-- Name: pga_exception_trigger; Type: TRIGGER; Schema: pgagent; Owner: postgres
--

CREATE TRIGGER pga_exception_trigger AFTER INSERT OR DELETE OR UPDATE ON pga_exception FOR EACH ROW EXECUTE PROCEDURE pga_exception_trigger();


--
-- Name: TRIGGER pga_exception_trigger ON pga_exception; Type: COMMENT; Schema: pgagent; Owner: postgres
--

COMMENT ON TRIGGER pga_exception_trigger ON pga_exception IS 'Update the job''s next run time whenever an exception changes';


--
-- Name: pga_job_trigger; Type: TRIGGER; Schema: pgagent; Owner: postgres
--

CREATE TRIGGER pga_job_trigger BEFORE UPDATE ON pga_job FOR EACH ROW EXECUTE PROCEDURE pga_job_trigger();


--
-- Name: TRIGGER pga_job_trigger ON pga_job; Type: COMMENT; Schema: pgagent; Owner: postgres
--

COMMENT ON TRIGGER pga_job_trigger ON pga_job IS 'Update the job''s next run time.';


--
-- Name: pga_schedule_trigger; Type: TRIGGER; Schema: pgagent; Owner: postgres
--

CREATE TRIGGER pga_schedule_trigger AFTER INSERT OR DELETE OR UPDATE ON pga_schedule FOR EACH ROW EXECUTE PROCEDURE pga_schedule_trigger();


--
-- Name: TRIGGER pga_schedule_trigger ON pga_schedule; Type: COMMENT; Schema: pgagent; Owner: postgres
--

COMMENT ON TRIGGER pga_schedule_trigger ON pga_schedule IS 'Update the job''s next run time whenever a schedule changes';


--
-- Name: pga_exception_jexscid_fkey; Type: FK CONSTRAINT; Schema: pgagent; Owner: postgres
--

ALTER TABLE ONLY pga_exception
    ADD CONSTRAINT pga_exception_jexscid_fkey FOREIGN KEY (jexscid) REFERENCES pga_schedule(jscid) ON UPDATE RESTRICT ON DELETE CASCADE;


--
-- Name: pga_job_jobagentid_fkey; Type: FK CONSTRAINT; Schema: pgagent; Owner: postgres
--

ALTER TABLE ONLY pga_job
    ADD CONSTRAINT pga_job_jobagentid_fkey FOREIGN KEY (jobagentid) REFERENCES pga_jobagent(jagpid) ON UPDATE RESTRICT ON DELETE SET NULL;


--
-- Name: pga_job_jobjclid_fkey; Type: FK CONSTRAINT; Schema: pgagent; Owner: postgres
--

ALTER TABLE ONLY pga_job
    ADD CONSTRAINT pga_job_jobjclid_fkey FOREIGN KEY (jobjclid) REFERENCES pga_jobclass(jclid) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: pga_joblog_jlgjobid_fkey; Type: FK CONSTRAINT; Schema: pgagent; Owner: postgres
--

ALTER TABLE ONLY pga_joblog
    ADD CONSTRAINT pga_joblog_jlgjobid_fkey FOREIGN KEY (jlgjobid) REFERENCES pga_job(jobid) ON UPDATE RESTRICT ON DELETE CASCADE;


--
-- Name: pga_jobstep_jstjobid_fkey; Type: FK CONSTRAINT; Schema: pgagent; Owner: postgres
--

ALTER TABLE ONLY pga_jobstep
    ADD CONSTRAINT pga_jobstep_jstjobid_fkey FOREIGN KEY (jstjobid) REFERENCES pga_job(jobid) ON UPDATE RESTRICT ON DELETE CASCADE;


--
-- Name: pga_jobsteplog_jsljlgid_fkey; Type: FK CONSTRAINT; Schema: pgagent; Owner: postgres
--

ALTER TABLE ONLY pga_jobsteplog
    ADD CONSTRAINT pga_jobsteplog_jsljlgid_fkey FOREIGN KEY (jsljlgid) REFERENCES pga_joblog(jlgid) ON UPDATE RESTRICT ON DELETE CASCADE;


--
-- Name: pga_jobsteplog_jsljstid_fkey; Type: FK CONSTRAINT; Schema: pgagent; Owner: postgres
--

ALTER TABLE ONLY pga_jobsteplog
    ADD CONSTRAINT pga_jobsteplog_jsljstid_fkey FOREIGN KEY (jsljstid) REFERENCES pga_jobstep(jstid) ON UPDATE RESTRICT ON DELETE CASCADE;


--
-- Name: pga_schedule_jscjobid_fkey; Type: FK CONSTRAINT; Schema: pgagent; Owner: postgres
--

ALTER TABLE ONLY pga_schedule
    ADD CONSTRAINT pga_schedule_jscjobid_fkey FOREIGN KEY (jscjobid) REFERENCES pga_job(jobid) ON UPDATE RESTRICT ON DELETE CASCADE;


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

