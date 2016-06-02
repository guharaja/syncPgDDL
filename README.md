# syncPGSchema
*maintain Postgresql schema in git*

This project has no automated setup yet.  It has to be setup by hand as 
described below.

It consists of 3 files:
 - *restore_schema.sh* - shell file called by git hook post-merge to apply
   the new schema
 - *setUpPgAgent.sql* - sql script to set-up database to dump schema on DDL 
 - a sample *post-merge* from [https://gist.github.com/sindresorhus/7996717](https://gist.github.com/sindresorhus/7996717)

**restore_schema.sh** has only been tested in parts, and only with a dummy database.  It needs rigourous testing.  Testing of the complete system will require the help of a volunteer.

The included **post-merge** file has been modified to function with the *restore_schema.sh* script.  It can be placed in the .git/hooks directory or its contents can be added to an existing hook file.

Though the **setUpPgAgent.sql** is tested and working, it assumes a fresh PgAgent install and truncates several tables at will.  This needs to be rectified ASAP.  The following are instructions for its setup.
 
*setUpPgAgent.sql* automates extraction of a postgres db schema upon any changes made to it.  The dump dir(sqls) should be set to a git-enabled area for version control of the text schema file.  

1) install PgAgent from Postgres Stack Builder
> when asked for a Windows User Account(henceforth `<WinUser>`), provide username and password of the owner of the git dir where the dump file will reside

2) add a line to `C:\Users\<WinUser>\AppData\Roaming\postgresql\pgpass.conf` to allow entry into the db to for the dump program; this line is of the format:
>   `[hostname]:[port]:[database]:[username]:[password]`
>   e.g. localhost:5432:sabyasachi:postgres:password

3) make changes to the setUpPgAgent.sql file; 
>	    1) settings in the section immediately below
>		    dbname - name of the database, e.g. 'sabyasachi'
>		    user - the database username e.g. 'password'
>		    sqls - the dir under git where the dump file will reside
>			    e.g. 'C:\\Users\\<WinUser>\\Documents\\sqls'
>		    prog - the full path and name of pg_dump.exe in PostgreSQL bin dir 
>			    e.g. 'C:\\Program Files\\PostgreSQL\.9.5\\bin\\pg_dump.exe'
>   		pass - the db password  - NO LONGER USED, set in *.pgpass* file 	
>   		errs - the errors file dir - NO LONGER USED
>   	2) IMPORTANT: SET PASSWORD IN FUNCTION *sched_pg_dump_run()*
>			( ON OR NEAR LINE 70 of *setUpPgAgent.sql* )
>		(There should be a better way, but fact and theory are in disagreement here.)

4) run setUpPgAgent.sql in the target database
>   	a) in PgAdmin click on the target database to select it
>	    b) open PSQL Console from the Plugins menu - should show db name in prompt
>   	c) type \cd <directory where setUpPgAgent.sql exists>
>   	d) type \i setUpForPgAgent.sql
>   	e) NOTE: THIS SCRIPT WILL TRUNCATE TABLES IN pgagent SCHEMA.  IF PgAgent
>		ON YOUR MACHINE IS NOT A NEW INSTALL, EXISTING DATA WILL BE LOST.
>   	f) should see the following near the end:
>   		. . . 
>	    	CREATE EXTENSION
>	    	CREATE FUNCTION
>		    CREATE EVENT TRIGGER
>		    . . .
>   	g) test
>   		create a test table in target database
>   			CREATE TABLE test_table ( id SERIAL, colA INTEGER );
>   	Successful completion of the CREATE statement indicates that the dump will start in 20 secs.  Ensure that file <dbname>.schema.sql appears in the dump dir(sqls) in a few minutes.  Time taken will depend on the size of the target database.
