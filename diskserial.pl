#!/usr/bin/perl -w

use strict;
use Data::Dumper;
use File::Copy;
use Getopt::Long;
use FindBin;
use lib $FindBin::Bin;
use DiskSerial;

my($init_newdb) = undef;
my($init_db) = undef;
my($compare) = undef;
my($nagios) = undef;
my($sha256) = undef;
my($help) = undef;
my($perf) = undef;

my($sha256sum) = "/usr/bin/sha256sum";
#$sha256sum = "sha256sum" unless ( -x $sha256sum );

my(%ERRORS) = ( 'OK' => 0, 'WARNING' => 1, 'CRITICAL' => 2, 'UNKNOWN' => 3, 'DEPENDENT' => 4 );

my(@wow) = qq(
Usage: $0
   --init ( create base database ) 
   --initnew ( create new database ) 
   --check|--compare ( compares init and initnew databases ) 
   --op5|--nagios (report like a nagios check)
   --perf ( include nagios performance output, age, removed and new disks )
   --sha256 | --sha256=<sha256sum> (Report or verify database checksum using sha256sum)
   --help  (This help)

Ways of working
===============

Step1: Initiate the base database.
# $0 --init

Step2: Retrieve the checksum of the database.
# $0 --sha256

Step3: Create a new database and verify against base database.
# $0 --initnew --check --sha256=<the output from Step2>

);

sub doexitcrit($) {
	my($text) = shift;
	chomp($text);

	if ( $nagios ) {
		print "CRITICAL: $text\n";
		exit($ERRORS{CRITICAL});
	}
	else  {
		print $text . "\n";
		exit(1);
	}
}

sub checksummer($$;$) {
	my($checksummer) = shift;
	my($filename) = shift;
	my($checksum) = shift;

	unless ( -x $checksummer ) {
		doexitcrit("$checksummer does not exists or is not an executable");
	}
	unless ( open(POPEN,"$checksummer $filename|") ) {
		doexitcrit("$checksummer $filename: $!");
	}
	my($cksum) = undef;
	foreach ( <POPEN> ) {
		next unless ( $_ );
		chomp;
		($cksum) = split(/\s+/,$_);
	}
	close(POPEN);
	unless ( $cksum ) {
		doexitcrit("Unable to get checksum using $checksummer on $filename");
	}
	if ( length($checksum) ) {
		if ( $checksum ne $cksum ) {
			doexitcrit("Incorrect checksum on $filename");
		}
	}
	else {
		print "$cksum\n";
		exit(0);
	}
}
	

sub usage() {
	foreach ( @wow ) {
		print "$_\n";
	}
}


GetOptions (
	"init" => \$init_db,
	"initnew" => \$init_newdb,
	"check|compare" => \$compare,
	"op5|nagios" => \$nagios,
	"perf" => \$perf,
	"sha256|sha256sum:s" => \$sha256,
	"help" => \$help,
)  or die("Error in command line arguments\n" . usage() . "\n");

if ( $help ) {
	usage();
	exit(0);
}

my($self) = new DiskSerial();
my($initdb) = "/var/tmp/diskserial.db";
if ( $init_db ) {
	$self->save_database($initdb);
}

my($newdb) = $initdb . ".new";
if ( $init_newdb ) {
	$self->save_database($newdb);
}

#
# Find out which checksum to use
#
my($checksummer) = undef;
my($checksum) = undef;
if ( defined($sha256) ) {
	$checksummer = $sha256sum;
	$checksum = $sha256;
}

#
# Execute checksum check or create
#
if ( $checksummer ) {	
	checksummer($checksummer,$initdb,$checksum);
}

unless ( $compare ) {
	if ( $init_db || $init_newdb ) {
		exit(0);
	}
	else {
		die usage() . "\n";
	}
}

my(@newdb) = $self->load_database($newdb);
my($age_newdb) = $self->age_database($newdb);

my(@initdb) = $self->load_database($initdb);
my($age_initdb) = $self->age_database($initdb);

my($agediff) = 0;
if ( $age_newdb && $age_initdb ) {
	$agediff = $age_newdb - $age_initdb;
	$agediff = int($agediff/(24*3600));
	#print "initdb= " . localtime($age_initdb) . "\n";
	#print "newdb=  " . localtime($age_newdb) . "\n";
	#print "agediff=$agediff\n";
}


my(%initdb);
my(%newdb);
foreach ( @newdb ) {
	next if ( m/^#/ );
	s/\s+/,/g;
	s/,$//;
	$newdb{$_}++;
}

foreach ( @initdb ) {
	next if ( m/^#/ );
	s/\s+/,/g;
	s/,$//;
	$initdb{$_}++;
}

my($removed_disks) = 0;
my($removed_disks_text) = undef;
my(@report) = ();
push(@report,"\nRemoved disks:");
foreach ( sort keys %initdb ) {
	next if ( $newdb{$_} );
	push(@report,$_);
	$removed_disks_text .= $_ . " ";
	$removed_disks++;
}

my($new_disks) = 0;
my($new_disks_text) = undef;
push(@report,"\nNew disks:");
foreach ( sort keys %newdb ) {
	next if ( $initdb{$_} );
	push(@report,$_);
	$new_disks_text .= $_ . " ";
	$new_disks++;
}

if ( $nagios ) {
	my($res) = "";
	my($error) = 0;

	if ( $new_disks ) {
		$res .= "New disks($new_disks): $new_disks_text, " . $res;
		$error = 1;
	}
	
	if ( $removed_disks ) {
		$res = "Removed disks($removed_disks): $removed_disks_text, " . $res;
		$error = 2;
	}
	
	$res =~ s/,\s*$//;
	$res =~ s/,/, /;
	if ( $perf ) {
		$res .= "| agediff=$agediff removed=$removed_disks new=$new_disks";
	}
	if ( $error > 1 ) {
		print "CRITICAL:" . $res . "\n";
	}
	elsif ( $error > 0 ) {
		print "WARNING:" . $res . "\n";
	}
	else {
		print "OK: No changes of disk serial numbers\n";
	}
	exit($error);
}
else {
	foreach ( @report ) {
		print "$_\n";
	}
	exit(0);
}
