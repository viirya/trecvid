
use IO::All;
use Getopt::Long;
use POSIX qw(ceil floor);


my $mapping_file = '';
my $output_file = '';

GetOptions ("mapping_file=s" => \$mapping_file, "output_file=s" => \$output_file);

my $mapping = io($mapping_file);
my $prev_video_id = 0;
my $shot_count = 0;
my $content = '';
while (my $line = $mapping->getline) {

  my $video_id;
  my $shot_seq;
  my $shot_id;
  if ($line =~ m/(.*?)\t(.*?)\t(.*)/) {
    $video_id = $1;
    $shot_seq = $2;
    $shot_id = $3;    
  }
  else {
    next;
  }

  if ($prev_video_id == $video_id) {
    $shot_count++;
  }
  else {
    $shot_count = 1;
  }

  $shot_id = "shot$video_id" . '_' . $shot_count;

  $prev_video_id = $video_id;

  print "$1 $2 $shot_id\n";
  $content .= "$1\t$2\t$shot_id\n";

}

$content > io($output_file);

exit;

