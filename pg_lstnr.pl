#!/usr/bin/perl
use Modern::Perl;
use DBI;
use IO::Select;

$| = 1;

my $dumpDir = '/home/rajag/Devel/sabya_db';
my $dumpExec = "$dumpDir/sabya_backup.sh";
my $dumpFn = "$dumpDir/sabya.schema.sql";

my $dbname = "sabyasachi";
my $dbuser = "sabyasachi";
my $dbpass = "password";
my $dbhost = "192.168.1.220";
my $dbattr = {RaiseError => 1, AutoCommit => 1};

my $dbh = DBI->connect("DBI:Pg:dbname=$dbname;host=$dbhost", $dbuser, $dbpass, $dbattr) 
	or die "cannot connect to db:$!\n";
$dbh->do( "LISTEN ddl_run;" );
my $sel = IO::Select->new( $dbh->{pg_socket} );
say "Listening for pg notifications on channel 'ddl_run' with pid $$ . . .";
while ( $sel->can_read ) {
	while ( my $notif = $dbh->pg_notifies ) {
		my ($name, $pid, $load) = @$notif;
		say "Rcvd $name from pid $pid : $load";
		my $stat = `$dumpExec $dumpFn`;
		say "$stat";
	}
}
say "Exiting listener for pg notifications on channel 'ddl_run' \\w pid $$";
$dbh->disconnect;

