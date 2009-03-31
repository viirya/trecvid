
use strict;
use XML::Simple;
use Data::Dumper;
use IO::All;
use Getopt::Long;
use POSIX qw(ceil floor);


my $keyframe_dir = '';
my $subshot_file = '';
my $output_file = '';
my $year = '';

GetOptions ("ss_file=s" => \$subshot_file, "kf_dir=s" => \$keyframe_dir, "output=s" => \$output_file, "year=s" => \$year);

if ($subshot_file eq '' || $keyframe_dir eq '' || $output_file eq '') {
  print "wrong parameters.\n";
  exit;
}

my @subshots = io($subshot_file)->slurp;
my $prev_video_id = '0';
my $sdb_file;
my $output_content = '';
foreach my $subshot (@subshots) {

  my $video_id;
  my $keyframe_num;
  my $subshot_id;

  if ($subshot =~ m/^(.*?)\s(.*?)\s(.*)/) {
    $video_id = $1;
    $keyframe_num = $2;
    $subshot_id = $3;
  }
  else {
    next;
  }

  print "$video_id $keyframe_num $subshot_id\n"; 

  if ($video_id ne $prev_video_id) {
    $sdb_file = io($keyframe_dir . '/' . 'TRECVID' . $year . '_' . $video_id . '.sdb');  
  }

  my $line = $sdb_file->getline;
  if ($line =~ m/(.*?)\s(.*?)\s(.*?)\s(.*?)\s(.*?)\s(.*)/) {
    $keyframe_num = $4 + 0;
  }

  print "$video_id $keyframe_num $subshot_id\n";

  $output_content .= "$video_id\t$keyframe_num\t$subshot_id\n";

  $prev_video_id = $video_id;
}

$output_content > io($output_file);

exit;

