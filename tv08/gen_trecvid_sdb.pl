
use strict;
use XML::Simple;
#use MediaTime;
use Data::Dumper;
use IO::All;
use Getopt::Long;
use POSIX qw(ceil floor);


my $shot_ref_dir = '';
my $video_def = '';
my $subshot_list_dir = '';
my $output_dir = '';
my $use = 'test';
my $year = '';

GetOptions ("video_df=s" => \$video_def, "shotref_dir=s" => \$shot_ref_dir, "sslist_dir=s" => \$subshot_list_dir, "output_dir=s" => \$output_dir, "use=s" => \$use, "year=s" => \$year);

if ($video_def eq '' || $shot_ref_dir eq '' || $subshot_list_dir eq '') {
  print "wrong parameters.\n";
  exit;
}

my $xs = XML::Simple->new();
my $col_doc = $xs->XMLin($video_def);
my %videos = %{$col_doc->{VideoFile}};
my %collects = {};

foreach my $vid (sort {$a <=> $b} keys %videos) {
  next unless defined($videos{$vid});

  print "parsing $vid.....\n";

  my $clip_name = $videos{$vid}->{filename};
  my $purpose = $videos{$vid}->{use};
  my $source = $videos{$vid}->{source};

  next if ($purpose ne $use);
	
  my $sdb_filename = 'TRECVID' . $year . '_' . $vid . '.sdb';
  my $trecvid_video_id = 'TRECVID' . $year . '_' . $vid;
  $collects{$vid}{'trecvid'} = $trecvid_video_id;
  $collects{$vid}{'video'} = $clip_name;
}

#print Dumper(%collects);

foreach my $id (keys %collects) {
  next if !defined $collects{$id};
 
  my $trecvid_video_id = $collects{$id}{'trecvid'}; 
  my $video_name = $collects{$id}{'video'};

  print "processing $id in $video_def.....\n ";

  my $shot_ref = io($shot_ref_dir . '/' . $video_name . '.sb'); 
  my @subshots = io($subshot_list_dir . '/' . $trecvid_video_id . '.txt')->slurp;

  my $current_shot;
  my $current_subshot = 0;
  my $used_in_sdb_file;
  my $rkf_in_sdb_file;
  my $prev_shot;
  my $sdb_content = '';
  foreach my $index (0..scalar(@subshots)-1) {
    my $subshot_line = $subshots[$index]; 
    my $next_subshot_line = '';
    $next_subshot_line = $subshots[$index + 1] if $index < scalar(@subshots)-1;

    my $shot_ref_line = $shot_ref->getline();
    my $eof = 0;
    while (!($shot_ref_line =~ m/^\d*\s\d*/)) {
      $shot_ref_line = $shot_ref->getline();
      if ($shot_ref_line eq '') {
        $eof = 1;
        last;
      }
    }
    last if $eof == 1;
   
    my $start_frame;
    my $end_frame;
    my $keyframe;
    my $subshot_length;

    if ($shot_ref_line =~ m/^(\d*)\s(\d*)/) {
      $start_frame = $1;
      $end_frame = $2;
      $keyframe = floor(($end_frame - $start_frame) / 2) + $start_frame;
      $subshot_length = $end_frame - $start_frame;
    }

    #print $subshot_line;
    #print $shot_ref_line;

    if ($subshot_line =~ m/shot$id\_(\d*)\_NRKF\_(\d*)/) {
      $current_shot = $1;
      $current_subshot = $2;
      $used_in_sdb_file = 1;
      $rkf_in_sdb_file = 0;
    }
    elsif ($subshot_line =~ m/shot$id\_(\d*)\_RKF/) {
      $current_shot = $1;

      if ($next_subshot_line =~ m/shot$id\_$current_shot\_NRKF\_(\d*)/) {
        $used_in_sdb_file = 0;
      }
      elsif ($prev_shot == $current_shot) {
        $used_in_sdb_file = 0;
      }
      else {
        $used_in_sdb_file = 1;
      }

      $rkf_in_sdb_file = 1;
    }
    
    $prev_shot = $current_shot; 

    $start_frame = sprintf("%.6d", $start_frame);
    $keyframe = sprintf("%.6d", $keyframe);

    $sdb_content .= "$start_frame\t$subshot_length\t$current_shot\t$keyframe\t$rkf_in_sdb_file\t$used_in_sdb_file\n";
  } 
  
  $sdb_content > io($output_dir . '/' . $trecvid_video_id . '.sdb');
}

exit;

