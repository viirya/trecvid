
use IO::All;

my $filename = $ARGV[0];

my $file = io($filename);
my $rkf_count = 0;
my $nrkf_count = 0;
while (my $line = $file->getline) {
  if ($line =~ m/_RKF/) {
    $rkf_count++; 
  }
  if ($line =~ m/_NRKF/) {
    $nrkf_count++;
  }
}

print "RFK: $rkf_count, NRKF: $nrkf_count\n";
exit;

