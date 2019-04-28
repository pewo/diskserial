package DiskSerial;

use strict;
use Carp;
use Data::Dumper;
use File::Basename;
use File::Copy;
use lib ".";
#use HashTools;
use Object;

my($debug) = 1;
$DiskSerial::VERSION = '0.01';
@DiskSerial::ISA = qw(Object);

sub new {
        my $proto = shift;
        my $class = ref($proto) || $proto;
        my $self  = {};
        bless($self,$class);

	my($dir) = "/local/robot/curr";

        my(%hash) = ( dir => $dir, @_ );
        while ( my($key,$val) = each(%hash) ) {
                $self->set($key,$val);
        }

	$dir = $self->get("dir");
	if ( ! -d $dir ) {
		chdir($dir);
		croak "$dir: $!";
	}
        return($self);
}

sub trim() {
	my($self) = shift;
	my($key) = shift;
	return(undef) unless ( defined($key) );
	$key =~ s/^\s+//;
	$key =~ s/\s+$//;
	return($key);
}

sub readfile() {
	my($self) = shift;
	my($file) = shift;
	my(@res) = ();
	if ( open(IN,"<$file") ) {
		foreach ( <IN> ) {
			chomp;
			push(@res,$_);
		}
		close(IN);
	}
	return(@res);
}

sub _getdir() {
	my($self) = shift;
	my($target) = shift;
	my($odir) = $self->get("dir");

	my($dir) = $odir . "/$target";
	unless ( -d $dir ) {
		my(@dirs) = ( <$odir/$target*> );
		my($tdir) = shift(@dirs);
		if ( defined($tdir ) ) {
			$dir = $tdir;
		}
	}
	if ( -d $dir ) {
		print "Returning [$dir] for [$target]\n" if ( $debug > 8);
		return($dir);
	}
	else{
		return(undef);
	}
}
	
sub inventory() {
	my($self) = shift;
	my($target) = shift;
	my($odir) = $self->get("dir");
	#
	# Without target, return the list of targets existing in directory
	#
	unless ( $target ) {
		my(@inv) = ();
		foreach ( <$odir/*> )  {
			push(@inv,basename($_));
		}
		return(@inv);
	}
	my($dir) = $odir . "/$target";
	unless ( -d $dir ) {
		my(@dirs) = ( <$odir/$target*> );
		my($tdir) = shift(@dirs);
		if ( defined($tdir ) ) {
			$dir = $tdir;
		}
	}
	unless ( -d $dir ) {
		return(undef);
	}

	my(%inv) = ();

	my($model) = undef;
	my($type) = undef;
	my($manu) = undef;
	my($serial) = undef;
	my($completed) = 0;

	my(@uname) = $self->readfile("$dir/uname_-a");
	
	#
	# model
	#
	if ( ! $model ) {
		# 
		# SPARC
		#
		if ( grep(/sparc/i,@uname) ) {
			if ( $uname[0] =~ /sparc\s+(.*)$/ ) {
				$model = $1;
				if ( $model =~ /SUNW/ ) {
					$manu = "Sun";
				}
			}
		}
	}

	#
	# Type
	#
	$type = "Physical Server";
	my(@eeprom) = $self->readfile("$dir/eeprom");
	if ( grep(/virtual-console/i,@eeprom) ) {
		$type = "Virtual Server";
	}
	elsif ( grep(/virtual/i,@uname) ) {
		$type = "Virtual Server";
	}
	elsif ( $model ) {
		if ( $model =~ /vmware/i ) {
			$type = "Virtual Server";
		}
	}
		

	
	$inv{manu}=$self->trim($manu) if ( $manu );
	$inv{type}=$self->trim($type) if ( $type );
	$inv{model}=$self->trim($model) if ( $model );

	return(%inv);
}

sub smartctl_info() {
	my($self) = shift;
	my($smartctl_info) = shift;
	my(@smartctl) = $self->readfile($smartctl_info);
	my($i) = 0;
	my(%disks);
	my(%tmp) = ();
	foreach ( @smartctl ) {
		if ( m/^\s*$/ ) {
			$i++;
		}
		if ( m/^Vendor.*:\s+(\w+)/i ) {
			$tmp{$i}{vendor}=$1;
			print "Adding $1 to vendor\n" if ( $debug > 8 );
		}
		elsif ( m/^Product.*:\s+(\w+)/i ) {
			$tmp{$i}{product}=$1;
			print "Adding $1 to product\n" if ( $debug > 8 );
		}
		elsif ( m/^Serial.*:\s+(\w+)/i ) {
			$tmp{$i}{serial}=$1;
			print "Adding $1 to serial\n" if ( $debug > 8 );
		}
		elsif ( m/^Device\s+Model.*:\s+(\w+)/i ) {
			$tmp{$i}{model}=$1;
			print "Adding $1 to model\n" if ( $debug > 8 );
		}
		elsif ( m/^Add.*Product.*Id.*:\s+(\w+.*)/i ) {
			$tmp{$i}{prodid}=$1;
			print "Adding $1 to prodid\n" if ( $debug > 8 );
		}
	}
	my($id);
	foreach $id ( keys %tmp ) {
		my($vendor) = $tmp{$id}{vendor};
		unless ( $vendor ) {
			$vendor = $tmp{$id}{prodid};
		}
		$disks{$id}{vendor}=$vendor;

		my($product) = $tmp{$id}{product};
		unless ( $product ) {
			$product = $tmp{$id}{model};
		}
		$disks{$id}{product} = $product;

		my($serial) = $tmp{$id}{serial};
		unless ( $serial ) {
			$serial = "unknown";
		}
		$disks{$id}{serial} = $serial;
	}
		
	return(%disks);
}

sub iostat_E() {
	my($self) = shift;
	my($iostat_E) = shift;
	my(@iostat_E) = $self->readfile($iostat_E);
	my($i) = 0;
	my(%disks);
	my(%tmp) = ();

	# Vendor: SEAGATE  Product: ST914602SSUN146G Revision: 0400 Serial No: 071891VHNV 

	foreach ( @iostat_E ) {
		$i++;
		if ( m/.*vendor:\s+(\w+)/i ) {
			$tmp{$i}{vendor}=$1;
		}
		if ( m/.*product:\s+(\w+)/i ) {
			$tmp{$i}{product}=$1;
		}
		if ( m/.*serial.*:\s+(\w+)/i ) {
			$tmp{$i}{serial}=$1;
		}
	}
	foreach ( sort keys %tmp ) {
		$disks{$_}{vendor} = $tmp{$_}{vendor} || "unknown";		
		$disks{$_}{product} = $tmp{$_}{product} || "unknown";		
		$disks{$_}{serial} = $tmp{$_}{serial} || "unknown";		
	}

	return(%disks);
}

sub getserial() {
	my($self) = shift;
	my($target) = shift;
	my($dir) = $self->_getdir($target);

	my(%disks) = ();
	my($iostat_E) = $dir . "/iostat_E";
	if ( -r $iostat_E ) {
		my(%iostat_E) = $self->iostat_E($iostat_E);
		return(%iostat_E);
	}
	my($smartctl_info) = $dir . "/smartctl_info";
	if ( -r $smartctl_info ) {
		my(%smartctl_info) = $self->smartctl_info($smartctl_info);
		return(%smartctl_info);
	}

	return(%disks);
}

sub disk_inv_racadm() {
	my($self) = shift;
	my($racadm) = shift;
	#Disk.Bay.0:Enclosure.Internal.0-1:RAID.Integrated.1-1
	#   Status                           = Ok                                       
	#   DeviceDescription                = Disk 0 in Backplane 1 of Integrated RAID Controller 1
	#   RollupStatus                     = Ok                                       
	#   Name                             = Physical Disk 0:1:0                      
	#   State                            = Online                                   
	#   OperationState                   = Not Applicable                           
	#   PowerStatus                      = Spun-Up                                  
	#   Size                             = 558.38 GB                                
	#   FailurePredicted                 = NO                                       
	#   RemainingRatedWriteEndurance     = Not Applicable                           
	#   SecurityStatus                   = Not Capable                              
	#   BusProtocol                      = SAS                                      
	#   MediaType                        = HDD                                      
	#   UsedRaidDiskSpace                = 558.38 GB                                
	#   AvailableRaidDiskSpace           = 0.00 GB                                  
	#   Hotspare                         = NO                                       
	#   Manufacturer                     = SEAGATE                                  
	#   ProductId                        = ST600MM0006                              
	#   Revision                         = LS0A                                     
	#   SerialNumber                     = S0M3SXYZ                                 
	#   PartNumber                       = CN07YX58726224AA09CPA02                  
	#   NegotiatedSpeed                  = 6.0 Gb/s                                 
	#   ManufacturedDay                  = 1                                        
	#   ManufacturedWeek                 = 41                                       
	#   ManufacturedYear                 = 2014                                     
	#   ForeignKeyIdentifier             = null                                     
	#   SasAddress                       = 0x5000C5007E1DA88D                       
	#   FormFactor                       = 2.5 Inch                                 
	#   RaidNominalMediumRotationRate    = 10000                                    
	#   T10PICapability                  = Not Capable                              
	#   BlockSizeInBytes                 = 512                                      
	#   MaxCapableSpeed                  = 6 Gb/s                                   
	#   SelfEncryptingDriveCapability    = Not Capable                  

        my(@racadm) = $self->readfile($racadm);
	my($i) = 0;
	my(%tmp) = ();
	#   Name                             = Physical Disk 0:1:0                      
	#   Manufacturer                     = SEAGATE                                  
	#   ProductId                        = ST600MM0006                              
	#   SerialNumber                     = S0M3SXYZ                                 
	#   PartNumber                       = CN07YX58726224AA09CPA02                  
	foreach ( @racadm ) {
		$i++ if ( m/^\w/ ) ;
		$_ = $self->trim($_);
		#print "$i $_\n";
		if ( m/^name\s+=\s+(.*)/i ) {
			$tmp{$i}{name}=$1;
		}
		elsif ( m/^manufacturer\s+=\s+(.*)/i ) {
			$tmp{$i}{manufacturer}=$1;
		}
		elsif ( m/^productid\s+=\s+(.*)/i ) {
			$tmp{$i}{productid}=$1;
		}
		elsif ( m/^serialnumber\s+=\s+(.*)/i ) {
			$tmp{$i}{serialnumber}=$1;
		}
		elsif ( m/^partnumber\s+=\s+(.*)/i ) {
			$tmp{$i}{partnumber}=$1;
		}
	}

	my(%disks) = ();
	foreach ( sort keys %tmp ) {
		$disks{$_}{name} = $tmp{$_}{name} || "unknown";
		$disks{$_}{manufacturer} = $tmp{$_}{manufacturer} || "unknown";
		$disks{$_}{productid} = $tmp{$_}{productid} || "unknown";
		$disks{$_}{serialnumber} = $tmp{$_}{serialnumber} || "unknown";
		$disks{$_}{partnumber} = $tmp{$_}{partnumber} || "unknown";
	}
	return(%disks);
}

sub expand_netapp_disk() {
	my($self) = shift;
	my($disk) = shift;
	my(@arr) = split(/\W/,$disk);
	my($newdisk) = "";
	foreach ( @arr ) {
		$newdisk .= sprintf("%02x.",hex($_));
	}
	$newdisk =~ s/\.$//;
	return($newdisk);
}

sub disk_inv_7mode() {
	my($self) = shift;
	my($indata) = shift;
	#   DISK      OWNER                    POOL   SERIAL NUMBER         HOME  
	#------------ -------------            -----  -------------         -------------  
	#0c.00.3      netapp    (123456789)    Pool0  MS3KNPTF              netapp    (123456789) 
	#0c.00.2      netapp    (123456789)    Pool0  MS33RNWF              netapp    (123456789) 
        my(@indata) = $self->readfile($indata);
	my(%tmp) = ();
	foreach ( @indata ) {
		my($disk,$owner,$ownerid,$pool,$serial,$home,$homeid) = split(/\s+/,$_);
		next unless ( defined($disk) );
		next unless ( $disk =~ /^\d/ );
		next unless ( defined($serial) );
		next unless ( $serial =~ /\w+/ );
		my($newdisk) = 	$self->expand_netapp_disk($disk);
		$tmp{$newdisk}=$serial;
	}

	my($i) = 0;
	my(%disks);
	foreach ( sort keys %tmp ) {
		$i++;
		$disks{$i}{disk}=$_;
		$disks{$i}{serial}=$tmp{$_};
	}
	return(%disks);
}

sub disk_inv_cdot() {
	my($self) = shift;
	my($indata) = shift;
	#disk!owner!serial-number!serialnumber!
	#Disk Name!Owner!Serial Number!Serial Number!
	#1.0.0!netapp!XYZZMYBV!XYZZMYBV!
	#1.0.1!netapp!XYZZJTGY!XYZZJTGY!
	#1.0.2!netapp!XYZZJWN3!XYZZJWN3!
	#1.0.3!netapp!XYZZMWR3!XYZZMWR3!
        my(@indata) = $self->readfile($indata);
	my(%tmp) = ();
	foreach ( @indata ) {
		my($disk,$owner,$serial) = split(/\!/,$_);
		next unless ( defined($disk) );
		next unless ( $disk =~ /^\d/ );
		next unless ( defined($serial) );
		next unless ( $serial =~ /\w+/ );
		my($newdisk) = 	$self->expand_netapp_disk($disk);
		$tmp{$newdisk}=$serial;
	}

	my($i) = 0;
	my(%disks);
	foreach ( sort keys %tmp ) {
		$i++;
		$disks{$i}{disk}=$_;
		$disks{$i}{serial}=$tmp{$_};
	}
	return(%disks);
}


sub disk_inv() {
	my($self) = shift;
	
	my($dir) = $self->get("dir");
	my($diskinv);
	my(%targets);
	foreach $diskinv ( <$dir/*/disk.*.inv.*> ) {
		next unless ( $diskinv =~ /cdot/ );
		my($basename) = basename($diskinv);
		next unless ( $basename );
		my($target) = undef;
		if ( $basename =~ /^disk\.(.*)\.inv\./ ) {
			$target = $1;
		}
		unless ( $target ) {
			die "Can't get target from string $basename, exiting...\n";
		}
		#print "basename: $basename, target: $target\n";
		$targets{$target}{source}=$diskinv;
		if ( $diskinv =~ /\.racadm$/ ) {
			$targets{$target}{decoder}="racadm";
			my(%tmp) = $self->disk_inv_racadm($diskinv);
			foreach ( sort keys %tmp ) {
				$targets{$target}{$_}=$tmp{$_};
			}
		}
		elsif ( $diskinv =~ /\.7mode$/ ) {
			$targets{$target}{decoder}="7mode";
			my(%tmp) = $self->disk_inv_7mode($diskinv);
			foreach ( sort keys %tmp ) {
				$targets{$target}{$_}=$tmp{$_};
			}
		}
		elsif ( $diskinv =~ /\.cdot$/ ) {
			$targets{$target}{decoder}="cdot";
			my(%tmp) = $self->disk_inv_cdot($diskinv);
			foreach ( sort keys %tmp ) {
				$targets{$target}{$_}=$tmp{$_};
			}
		}
	}
	return(%targets);
}


sub generate_database() {
	my($self) = shift;
	
	my(@inv) = $self->inventory();
	my(@db) = ();

	#
	# Get all remote collected disk inventory
	#
	my(%disk_inv) = $self->disk_inv();
	my($target);
	foreach $target ( sort keys %disk_inv ) {
		my($decoder) = $disk_inv{$target}{decoder} || "unknown";
		delete($disk_inv{$target}{decoder});
		my($source) = $disk_inv{$target}{source} || "unknown";
		delete($disk_inv{$target}{source});
		my($server) = "Target: $target, decoder: $decoder, source: $source";
		my($hp) = $disk_inv{$target};
		my($i);
		push(@db,"#");
		push(@db,"# $server");
		push(@db,"#");
		foreach $i ( sort { $a <=> $b } keys %$hp ) {
			my($disk) = "target=$target ";
			my($diskhp) = $hp->{$i};
			foreach ( sort keys %$diskhp ) {
				$disk .= "$_=$diskhp->{$_} ";
			}
			push(@db,$disk);
		}
	}

	#
	# Get all local disk inventory
	#
	foreach $target ( sort @inv ) {
		#next unless ( $target =~ /oob/ );
		my($server) = "Target: $target";
		my(%target) = $self->inventory($target);
		foreach ( sort keys %target ) {
			$server .= ", $_: $target{$_} ";
		}
		push(@db,"#");
		push(@db,"# $server");
		push(@db,"#");
		my(%disks) = $self->getserial($target);
		my($i);

		#
		# Find max length of all values
		#
		my(%max);
		foreach $i ( sort keys %disks ) {
			my($hp) = $disks{$i};
			foreach ( sort keys %$hp ) {
				next unless ( defined($hp->{$_} ) );
				my($curr_val_len) = $max{$_}{val} || 0;
				if ( length($hp->{$_}) > $curr_val_len ) {
					$max{$_}{val} = length($hp->{$_});
				}
			}
		}

		#
		# Use tha max length for each value
		#
		foreach $i ( sort keys %disks ) {
			my($disk) = "target=$target ";
			my($hp) = $disks{$i};
			foreach ( sort keys %$hp ) {
				next unless ( defined($hp->{$_} ) );
				#$disk .= "$_=$hp->{$_}\t";
				$disk .= sprintf("%s=%-*.*s ",$_, $max{$_}{val}, $max{$_}{val}, $hp->{$_});
			}
			push(@db,$disk);
		}
	}
	return(@db);
}

sub save_database() {
	my($self) = shift;
	my($db) = shift;
	
	my($old) = $db . ".old";
	my(@db) = $self->generate_database();
	
	unlink($old);
	move($db,$old);
	unlink($old);
	
	unless ( open(DB,">$db") ) {
		die "Writing to $db: $!\n";
	}
	foreach ( @db ) {
		print DB $_ . "\n";
	}
	close(DB);

	return(@db);
}

sub load_database() {
	my($self) = shift;
	my($db) = shift;
	
	my(@db) = ();
	
	unless ( open(DB,"<$db") ) {
		die "Reading from $db: $!\n";
	}
	foreach ( <DB> ) {
		chomp;
		push(@db,$_);
	}
	close(DB);

	return(@db);
}
	
1;
