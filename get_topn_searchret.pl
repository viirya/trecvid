
use IO::All;
use Getopt::Long;
use Data::Dumper;


my $ret_dir;
my $output_dir;
my $n = 3000;

GetOptions ("searchret_dir=s" => \$ret_dir, "output_dir=s" => \$output_dir, "n=i" => \$n);

my $all_search = io($ret_dir);
my @ret_files = @$all_search;

foreach my $file (@ret_files) {
  
  if ($file =~ m/.*\/(.*?)\.txt/) {
    print "$file.....\n";
    my $filename = $1;
    my $file_content = io($file);
    my $count = 0;
    my $content = '';
    while (my $line = $file_content->getline) {
      last if $count >= $n;
      $content .= "$line"; 
      $count++;
    }
    $content > io($output_dir . "/" . $filename . ".txt"); 
  }
}

exit;

