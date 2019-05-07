package Object;


use strict;
use Carp;
use vars qw($VERSION);

$VERSION = '0.01';

sub set($$$) {
        my($self) = shift;
        my($what) = shift;
        my($value) = shift;

        $what =~ tr/a-z/A-Z/;

        $self->{ $what }=$value;
        return($value);
}

sub get($$) {
        my($self) = shift;
        my($what) = shift;

        $what =~ tr/a-z/A-Z/;
        my $value = $self->{ $what };

        return($self->{ $what });
}

sub new {
        my $proto  = shift;
        my $class  = ref($proto) || $proto;
        my $self   = {};

        bless($self,$class);

        my(%args) = @_;

        my($key,$value);
        while( ($key, $value) = each %args ) {
                $key =~ tr/a-z/A-Z/;
                $self->set($key,$value);
        }

        return($self);
}

package DiskSerial;

use strict;
use Carp;
use Data::Dumper;
use File::Basename;
use File::Copy;
#use lib ".";
#use HashTools;
#use Object;

my($debug) = 1;
$DiskSerial::VERSION = '0.01';
@DiskSerial::ISA = qw(Object);

sub new {
        my $proto = shift;
        my $class = ref($proto) || $proto;
        my $self  = {};
        bless($self,$class);

	my($dir) = "/local/robot/curr:/local/robot/static";

        my(%hash) = ( dir => $dir, @_ );
        while ( my($key,$val) = each(%hash) ) {
                $self->set($key,$val);
        }

	foreach $dir ( split(/:/,$self->get("dir")) ) {
		if ( ! -d $dir ) {
			chdir($dir);
			croak "$dir: $!";
		}
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

	my($dir) = undef;
	my($odir);
	foreach $odir ( split(/:/,$self->get("dir")) ) {
		my($tdir) = $odir . "/$target";
		if ( -d $tdir ) {
			$dir = $tdir;
		}
		else {
			my(@dirs) = ( <$odir/$target*> );
			($tdir) = shift(@dirs);
			if ( defined($tdir ) ) {
				$dir = $tdir;
			}
		}
	}
	if ( $dir ) {
		if ( -d $dir ) {
			print "Returning [$dir] for [$target]\n" if ( $debug > 8);
			return($dir);
		}
	}
	else{
		return(undef);
	}
}
	
sub inventory() {
	my($self) = shift;
	my($target) = shift;
	#
	# Without target, return the list of targets existing in directory
	#
	unless ( $target ) {
		my(@inv) = ();
		my($odir);
		foreach $odir ( split(/:/,$self->get("dir")) ) {
			foreach ( <$odir/*> )  {
				push(@inv,basename($_));
			}
		}
		#print "DEBUG " . Dumper(\@inv)  . "\n";
		return(@inv);
	}

	my($dir) = undef;
	my($odir);
	foreach $odir ( split(/:/,$self->get("dir") ) ) {
		my($tdir) = $odir . "/$target";
		if ( -d $tdir ) {
			$dir = $tdir;
		}
		else {
			my(@dirs) = ( <$tdir/$target*> );
			($tdir) = shift(@dirs);
			if ( defined($tdir) ) {
				$dir = $tdir;
			}
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
	my($rule) = "static";
	my(@lspci) = $self->readfile("$dir/lspci");
	my(@eeprom) = $self->readfile("$dir/eeprom");
	my(@type) = $self->readfile("$dir/type");

	if ( grep(/virtual/i,@type ) ) {
		$type = "Virtual Server";
		$rule = "type";
	}
	#elsif ( grep(/virtual-console/i,@eeprom) ) {
	#	$type = "Virtual Server";
	#	$rule = "eeprom";
	#}
	elsif ( grep(/virtual/i,@uname) ) {
		$type = "Virtual Server";
		$rule = "uname";
	}
	elsif ( $model ) {
		if ( $model =~ /vmware/i ) {
			$type = "Virtual Server";
			$rule = "model";
		}
	}
	if ( grep(/vmware/i,@lspci) ) {
		$type = "Virtual Server";
		$rule = "lspci";
	}
		
	$inv{manu}=$self->trim($manu) if ( $manu );
	$inv{type}=$self->trim($type) if ( $type );
	$inv{rule}=$self->trim($rule) if ( $rule );
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
		elsif ( m/^Serial.*:\s+(\w+.*)/i ) {
			my($serial) = $1;
			$serial =~ s/\W//g;
			$tmp{$i}{serial}=$serial;
			print "Adding $serial to serial\n" if ( $debug > 8 );
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

sub count_serials() {
	my($self) = shift;
	my(%hash) = @_;

	my($serials) = 0;
	foreach ( keys %hash ) {
		my($hp) = $hash{$_};
		foreach ( keys %$hp ) {
			#print "DEBUG count_serial, key=[$_], serials=[$serials]\n";
			next unless ( $_ =~ /serial/i );
			next unless ( length($hp->{$_}) );
			next if ( $hp->{$_} =~ /unknown/ );
			$serials++;
		}
	}
	return($serials);
}

sub getage() {
	my($self) = shift;
	my($file) = shift;
	return int( (100 * -M $file)) / 100;
}

sub getserial() {
	my($self) = shift;
	my($target) = shift;
	my($dir) = $self->_getdir($target);
	my(%info) = ( "source" => "unknown", "age" => "unknown");
	#return unless ( $target =~ /ezri/ );
	#print "DEBUG getserial dir=[$dir]\n";

	my(%disks) = ();
	my($iostat_E) = $dir . "/iostat_E";
	if ( -r $iostat_E ) {
		my($age) = $self->getage($iostat_E);
		$info{age}=$age;
		$info{source}=$iostat_E;
		my(%iostat_E) = $self->iostat_E($iostat_E);
		my($serials) = 0;
		$serials = $self->count_serials(%iostat_E);
		#print "DEBUG iostat_E serials: $serials\n";
		if ( $serials ) {
			#print Dumper(\%iostat_E);
			return(\%info, %iostat_E);
		}
	}
	my($prtconf) = $dir . "/prtconf";
	if ( -r $prtconf ) {
		my($age) = $self->getage($prtconf);
		$info{age}=$age;
		$info{source}=$prtconf;
		my(%prtconf) = $self->inv_prtconf($prtconf);
		#print "DEBUG jaffa prtconf: " . Dumper(\%prtconf);
		my($serials) = 0;
		$serials = $self->count_serials(%prtconf);
		if ( $serials ) {
			#print Dumper(\%prtconf);
			return(\%info, %prtconf);
		}
	}
		
	my($smartctl_info) = $dir . "/smartctl_info";
	if ( -r $smartctl_info ) {
		my($age) = $self->getage($smartctl_info);
		$info{age}=$age;
		$info{source}=$smartctl_info;
		my(%smartctl_info) = $self->smartctl_info($smartctl_info);
		return(\%info, %smartctl_info);
	}

	return(\%info, %disks);
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
		elsif ( m/^serial.*\s+=\s+(.*)/i ) {
			$tmp{$i}{serial}=$1;
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
		$disks{$_}{serial} = $tmp{$_}{serial} || "unknown";
		$disks{$_}{partnumber} = $tmp{$_}{partnumber} || "unknown";
	}
	return(%disks);
}


sub inv_prtconf() {
	my($self) = shift;
	my($prtconf) = shift;

	my(@prtconf) = $self->readfile($prtconf);
	my($indisk) = 0;
	my($line) = 0;
	my(%names);
	my($name) = "";
	my($value) = "";
	my($i) = 0;
	foreach ( @prtconf ) {
		$line++;
		s/^\s+//;
		if ( m/^disk.*instance/i ) {
			$indisk++;
			next;
		}
		if ( m/^\w+,\s+instance/i ) {
			$indisk=0;
			next;
		}
	
		next unless ( $indisk );
		chomp;
		$i++ if ( m/inquiry-serial-no/ );
	
		if ( m/^name/ ) {
			$name = $_;
			#print "$line\t$indisk\t$name";
		}
		if ( m/^value/ ) {
			s/value=//;
			s/\'//g;
			$value = $_;
			#print "$line\t$indisk\t$value";
			$names{$i}{$name}=$value;
		}
	
	}

	my(%keys) = (
		"client-guid"		=> "guid",
		"inquiry-product-id"	=> "product",
		"inquiry-serial-no"	=> "serial",
		"inquiry-vendor-id"	=> "vendor",
	);


	my(%disks);
	foreach $i ( sort keys %names ) {
		my($hp) = $names{$i};
		foreach ( sort keys %$hp ) {
			my($key);
			foreach  $key ( sort keys %keys ) {
				if ( $_ =~ /name.*$key/ ) {
					$disks{$i}{$keys{$key}}=$hp->{$_};
				}
			}
		}
	}

	#print Dumper(\%disks);
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
		$serial =~ s/\W//g;
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
	
	my($dir);

	my(%targets);
	foreach $dir ( split(/:/,$self->get("dir")) ) {
		#print "DEBUG disk_inv dir=$dir\n";
		#my($dir) = $self->get("dir");
		my($diskinv);
		foreach $diskinv ( <$dir/*/disk.*.inv.*> ) {
			#print "DEBUG disk_inv $dir $diskinv\n";
			#next unless ( $diskinv =~ /cdot/ );
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
			$targets{$target}{age}=$self->getage($diskinv);
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
			elsif ( $diskinv =~ /\.smartctl$/ ) {
				$targets{$target}{decoder}="smartctl";
				my(%tmp) = $self->smartctl_info($diskinv);
				foreach ( sort keys %tmp ) {
					$targets{$target}{$_}=$tmp{$_};
				}
			}
				
		}
	}
	#print "DEBUG " . Dumper(\%targets);
	return(%targets);
}


sub generate_database() {
	my($self) = shift;
	
	my(@inv) = $self->inventory();
	#my(@db) = ();

	my(%db);
	#
	# Get all remote collected disk inventory
	#
	my(%disk_inv) = $self->disk_inv();
	my($target);
	foreach $target ( sort keys %disk_inv ) {
		my(@db) = ();
		my($decoder) = $disk_inv{$target}{decoder} || "unknown";
		delete($disk_inv{$target}{decoder});
		my($source) = $disk_inv{$target}{source} || "unknown";
		delete($disk_inv{$target}{source});
		my($age) = $disk_inv{$target}{age} || "unknown";
		delete($disk_inv{$target}{age});
		#my($server) = "Target: $target, decoder: $decoder, source: $source";
		my($hp) = $disk_inv{$target};
		my($i);
		push(@db,"#");
		push(@db,"# target: $target");
		push(@db,"# decoder: $decoder");
		push(@db,"# source: $source");
		push(@db,"# age: $age");
		push(@db,"#");
		my($disks) = 0;
		my($serials) = 0;
		foreach $i ( sort { $a <=> $b } keys %$hp ) {
			my($disk) = "target=$target ";
			my($diskhp) = $hp->{$i};
			foreach ( sort keys %$diskhp ) {
				$disk .= "$_=$diskhp->{$_} ";
			}
			push(@db,$disk);
			$disks++;
			next if ( $disk =~ /serial=unknown/ );
			$serials++ 
		}
		push(@db,"# $target: disks: $disks, serial: $serials");
		$db{$target}=\@db;
	}

	#
	# Get all local disk inventory
	#
	foreach $target ( sort @inv ) {
		my(@db) = ();
		#next unless ( $target =~ /canis/ );
		#my($server) = "Target: $target";
		#print "DEBUG target=[$target]\n";
		my(%target) = $self->inventory($target);
		my($type) = $target{type} || "unknown";
		my($rule) = $target{rule} || "unknown";
		next if ( $type =~ /virtual/i );
		print "target: $target, type: $type, rule: $rule\n";
		push(@db,"#");
		push(@db,"# target: $target");
		foreach( sort keys %target ) {
			push(@db,"# $_: $target{$_}");
		}
		my($info, %disks) = $self->getserial($target);
		if ( $info ) {
			push(@db,"# source: " . $info->{"source"});
			push(@db,"# age: " . $info->{"age"});
		}
		push(@db,"#");
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
		my($disks) = 0;
		my($serials) = 0;
		foreach $i ( sort keys %disks ) {
			my($disk) = "target=$target ";
			my($hp) = $disks{$i};
			foreach ( sort keys %$hp ) {
				next unless ( defined($hp->{$_} ) );
				#$disk .= "$_=$hp->{$_}\t";
				$disk .= sprintf("%s=%-*.*s ",$_, $max{$_}{val}, $max{$_}{val}, $hp->{$_});
			}
			push(@db,$disk);
			$disks++;
			next if ( $disk =~ /serial=unknown/ );
			$serials++;
		}
		push(@db,"# $target: disks: $disks, serial: $serials");
		$db{$target}=\@db;
	}
	my(@db);
	foreach ( sort keys %db ) {
		my($ap) = $db{$_};
		foreach ( @$ap ) {
			push(@db,$_);
		}
	}
	return(@db);
}

sub save_database() {
	my($self) = shift;
	my($db) = shift;
	my($verbose) = $db . ".verbose";
	
	my($old) = $db . ".old";
	my($oldverbose) = $verbose . ".old";

	my(@db) = $self->generate_database();
	
	unlink($old);
	unlink($oldverbose);
	move($db,$old);
	move($verbose,$oldverbose);
	
	unless ( open(DB,">$db") ) {
		die "Writing to $db: $!\n";
	}
	unless ( open(VERBOSE,">$verbose") ) {
		die "Writing to $verbose $!\n";
	}
	foreach ( @db ) {
		print VERBOSE $_ . "\n";
		print DB $_ . "\n" unless ( m/^#/ );
	}
	close(DB);
	close(VERBOSE);

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

sub age_database() {
	my($self) = shift;
	my($db) = shift;
	
	my($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,
                   $atime,$mtime,$ctime,$blksize,$blocks)
                       = stat($db);

	return($mtime);
}
1;
