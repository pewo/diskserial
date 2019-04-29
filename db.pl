#!/usr/bin/perl -w

use strict;
use Data::Dumper;
use File::Copy;
use Getopt::Long;
use FindBin;
use lib $FindBin::Bin;
use DiskSerial;

my($usage) = "$0\n";
$usage .= "\t--newdb ( create new database ) \n";
$usage .= "\t--olddb ( create old database ) \n";
$usage .= "\t--check|--compare ( compares old and new databases ) \n";
$usage .= "\t--op5|--nagios (report like a nagios check)\n";

my($create_olddb) = undef;
my($create_newdb) = undef;
my($compare) = undef;
my($nagios) = undef;
GetOptions (
	"newdb" => \$create_newdb,
	"olddb" => \$create_olddb,
	"check|compare" => \$compare,
	"op5|nagios" => \$nagios,
)  or die("Error in command line arguments\n$usage\n");

my($self) = new DiskSerial();
my($olddb) = "/var/tmp/diskserial.db.old";
if ( $create_olddb ) {
	print "Initiating old database ($olddb)\n";
	$self->save_database($olddb);
	exit(0);
}

my($newdb) = "/var/tmp/diskserial.db.new";
if ( $create_newdb ) {
	print "Creating new database ($newdb)\n";
	$self->save_database($newdb);
	exit(0);
}

unless ( $compare ) {
	die "Usage: $usage\n";
}

my(@newdb) = $self->load_database($newdb);
my(@olddb) = $self->load_database($olddb);

my(%olddb);
my(%newdb);
foreach ( @newdb ) {
	next if ( m/^#/ );
	s/\s+/,/g;
	s/,$//;
	$newdb{$_}++;
}

foreach ( @olddb ) {
	next if ( m/^#/ );
	s/\s+/,/g;
	s/,$//;
	$olddb{$_}++;
}

my($removed_disks) = undef;
my(@report) = ();
push(@report,"\nRemoved disks:");
foreach ( sort keys %olddb ) {
	next if ( $newdb{$_} );
	push(@report,$_);
	$removed_disks .= $_ . " ";
}

my($new_disks) = undef;
push(@report,"\nNew disks:");
foreach ( sort keys %newdb ) {
	next if ( $olddb{$_} );
	push(@report,$_);
	$new_disks .= $_ . " ";
}

if ( $nagios ) {
	my($res) = "";
	my($error) = 0;

	if ( $new_disks ) {
		$res .= "New disks: $new_disks, " . $res;
		$error = 1;
	}
	
	if ( $removed_disks ) {
		$res = "Removed disks: $removed_disks, " . $res;
		$error = 2;
	}
	
	$res =~ s/,\s*$//;
	$res =~ s/,/, /;
	if ( $error > 1 ) {
		print "CRITICAL:" . $res . "\n";
	}
	elsif ( $error > 0 ) {
		print "WARNING:" . $res . "\n";
	}
	else {
		print "OK: No disk changes\n";
	}
	exit($error);
}
else {
	foreach ( @report ) {
		print "$_\n";
	}
	exit(0);
}
