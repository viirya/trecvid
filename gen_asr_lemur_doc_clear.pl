
use IO::All;
use Getopt::Long;
use XML::Simple;

my $tv_year = 'tv05';
my $sliding_window = 5;
my $window_right_shift = 0;
my $window_left_shift = 0;
my $video_def;
my $use = 'test';
my $output_filename = '';

GetOptions ("video_def=s" => \$video_def, "y=s" => \$tv_year, "w=i" => \$sliding_window, "rs=i" => \$window_right_shift, "ls=i" => \$window_left_shift, "use=s" => \$use, "out=s" => \$output_filename);

my $year;
$year = '2005' if ($tv_year eq 'tv05');
$year = '2006' if ($tv_year eq 'tv06');
$year = '2007' if ($tv_year eq 'tv07');
$year = '2008' if ($tv_year eq 'tv08');

print "generating lemur document for $tv_year\n";

my $xs = XML::Simple->new();
my $col_doc = $xs->XMLin($video_def);
my %videos = %{$col_doc->{VideoFile}};
my %collects = {};

foreach my $vid (sort {$a <=> $b} keys %videos) {
  next unless defined($videos{$vid});

  my $clip_name = $videos{$vid}->{filename};
  my $purpose = $videos{$vid}->{use};
  my $source = $videos{$vid}->{source};

  next if ($purpose ne $use);

  my $trecvid_video_id = 'TRECVID' . $year . '_' . $vid;
  $collects{$vid}{'trecvid'} = $trecvid_video_id;
  $collects{$vid}{'video'} = $clip_name;
}

my $doc = '';

my %number_of_subshots;

my %subshots;
my $subshot_by_kframe = io("$tv_year/$tv_year.subshots.all.txt");
while (my $subshot_line = $subshot_by_kframe->getline) {
  if ($subshot_line =~ m/(.*?)\s(.*?)\s(.*?)\s/) {
    my $video_id = $1;
    my $kframe = $2;
    my $subshot_id = $3;
  
    next unless defined($collects{$video_id});
  
    $subshots{$video_id}{$kframe} = $subshot_id;

    $number_of_subshots{$video_id}{'max'} = $3 if $3 > $number_of_subshots{$video_id}{'max'} || !defined $number_of_subshots{$video_id}{'max'};
    $number_of_subshots{$video_id}{'min'} = $3 if $3 > $number_of_subshots{$video_id}{'max'} || !defined $number_of_subshots{$video_id}{'min'};
  }
}

my $shot_count = 0;

for (@{io "$tv_year/asr_mt/"}) {
 
  my $video_id = '';
  if ($_ =~ m/TRECVID$year\_(.*)\.tkn/) {
    $video_id = $1;
  }
  else {
    next;
  }


  next unless defined($collects{$video_id});

  print "indexing " . $_ . ".....\n";

  print "reading $tv_year/keyframes/TRECVID$year" . "_" . "$video_id.sdb.....\n";

  my %kframes;
  my $ssdb = io("$tv_year/keyframes/TRECVID$year" . "_" . $video_id . '.sdb');
  my $frame_start = 0;
  my $frame_end = 0;
  my $shot_id = 0;
  while (my $ssdb_line = $ssdb->getline) {
    next if ($ssdb_line =~ m/^%/);

    if ($ssdb_line =~ m/(.*?)\s(.*?)\s(.*?)\s(.*?)\s(.*?)\s(.*)/) {
      my $frame_kframe = $4 + 0;
      my $used_as_kframe = $6 + 0;
      my $frame_kframe_id = $4;
      
      if ($1 + 0 == $frame_start && $frame_start != 0 || $shot_id == $3 + 0) {
        $frame_start = $frame_end + 1;
      }
      else {
        $frame_start = $1 + 0;
      }

      $shot_id = $3 + 0;

      $frame_end = $frame_kframe + ($frame_kframe - $frame_start);

      if ($used_as_kframe == 1) {
        $kframes{$frame_start} = $frame_kframe_id;
      }    
    }
  }

  my $raw_asr_mt = io($_);
  my @asr_mt;
  my %shot_number;
  my %asr_by_frame;

  while ($raw_asr_mt->getline =~ m/(.*?)\s(.*?)\s(.*)/) {
    my $time1 = $1;
    my $time2 = $2;
    my $text = $3;

    my ($sec1, $sec2, $fra1, $fra2) = (0, 0, 0, 0);
    if ($time1 =~ m/(.*?)\.(\d)(\d)/) {
      $sec1 = $1 + 0;
      $fra1 = $2 * 10 + $3;
    }
    else {
      $sec1 = $time1;
    }
    if ($time2 =~ m/(.*?)\.(\d)(\d)/) {
      $sec2 = $1 + 0;
      $fra2 = $2 * 10 + $3;
    }
    else {
      $sec2 = $time2;
    }

    my $frame_num_start;
    my $frame_num_end;

    if ($year eq '2005') {
      $frame_num_start = round(($sec1 * 30000 + $fra1) / 1001);
      $frame_num_end = round(($sec2 * 30000 + $fra2) / 1001);
    }
    else {
     $frame_num_start = round($time1 * 25); 
     $frame_num_end = round($time2 * 25);
    }
 
    if (!defined $asr_by_frame{$frame_num_start . '-' . $frame_num_end}) {
      $asr_by_frame{$frame_num_start . '-' . $frame_num_end} = [];
    }
 
    push @{$asr_by_frame{$frame_num_start . '-' . $frame_num_end}}, $text;

    $shot_number{$time1.$time2}++;

  }

  my @sorted_frame = sort {
    my $frame_num_start_a;
    my $frame_num_end_a;
    my $frame_num_start_b;
    my $frame_num_end_b;

    if ($a =~ m/(.*?)-(.*)/) {
      $frame_num_start_a = $1;
      $frame_num_end_a = $2;
    }
 
    if ($b =~ m/(.*?)-(.*)/) {
      $frame_num_start_b = $1;
      $frame_num_end_b = $2;
    }

    return $frame_num_end_a + 0 <=> $frame_num_end_b + 0; } keys %asr_by_frame;


  my %asr_by_subshot_id;
  foreach my $frames (@sorted_frame) {
    my $frame_num_start;
    my $frame_num_end;

    if ($frames =~ m/(.*?)-(.*)/) {
      $frame_num_start = $1;
      $frame_num_end = $2;
    }
    else {
      next;
    }

    my $kframe_located_start = 0;
    my $kframe_located_end = 0;
    my $mode = 0;
    foreach my $kframe_start (sort {$a + 0 <=> $b + 0} keys %kframes) {
      if ($mode == 0) {
        if ($kframe_start <= $frame_num_start) {
          $kframe_located_start = $kframe_start;
          $kframe_located_end = $kframe_start;
          next;
        }
        else {
          $mode = 1;
        }
      }
      if ($mode == 1) {
        if ($kframe_start <= $frame_num_end) {
          $kframe_located_end = $kframe_start;
          next;
        }
        else {
          last;
        }
      }
    }
   
    $kframe_located_start += 0;
    $kframe_located_end += 0;


    my $kframe_id_start = $kframes{$kframe_located_start} + 0;
    my $kframe_id_end = $kframes{$kframe_located_end} + 0;

    my $subshot_start = $subshots{$video_id}{$kframe_id_start};
    my $subshot_end = $subshots{$video_id}{$kframe_id_end};

    print "subshot: $subshot_start to $subshot_end\n";

    my $asr = $asr_by_frame{$frames};


    my $asr_length = scalar(@{$asr});
    my $subshot_index = $subshot_start;

    my %cache_of_asr;
    my $overlap = 0;
    foreach (0..($subshot_end - $subshot_start)) {
      my $start_index = $asr_length / ($subshot_end - $subshot_start + 1) * $_;
      my $end_index = $asr_length / ($subshot_end - $subshot_start + 1) * ($_ + 1) - 1;

      $start_index = $asr_length - 1 if ($start_index >= $asr_length);
      $end_index = $asr_length - 1 if ($end_index >= $asr_length);

      my @asr_of_subshot;
      foreach ($start_index..$end_index) {
        push @asr_of_subshot, $asr->[$_]; 
      }

      my %asr_hash;

      foreach (@asr_of_subshot) {
        $asr_hash{trim($_)} = 1;
      }
      
      if (defined $asr_by_subshot_id{$subshot_index + $_}) {
        my @dup_asr_of_subshot = split ' ', $asr_by_subshot_id{$subshot_index + $_};
          foreach (@dup_asr_of_subshot) {
            if (defined $asr_hash{trim($_)}) {
              undef $asr_hash{trim($_)};
              $overlap = 1;
            }
          }
      } 

      if ($overlap == 1) {
        $cache_of_asr{$subshot_index + $_ + 1} = join ' ', @asr_of_subshot;
      }

      foreach (0..scalar(@asr_of_subshot)-1) {
        if (!defined $asr_hash{trim($asr_of_subshot[$_])}) {
          delete $asr_of_subshot[$_];
        }    
      }


      $asr_by_subshot_id{$subshot_index + $_} .= ' ' . join ' ', @asr_of_subshot; 


      if (defined $cache_of_asr{$subshot_index + $_} && $cache_of_asr{$subshot_index + $_} ne '') {
        $asr_by_subshot_id{$subshot_index + $_} .= ' ' . $cache_of_asr{$subshot_index + $_};
        $cache_of_asr{$subshot_index + $_} = '';
        $overlap = 0;
      }
      $overlap = 0 if $overlap == 1;

    }
  }

  foreach ($number_of_subshots{$video_id}{'min'}..$number_of_subshots{$video_id}{'max'}) {
    if (!defined $asr_by_subshot_id{$_}) {
      $asr_by_subshot_id{$_} = '';
    }
  }

  my @subshot_sorted_ids = sort {$a + 0 <=> $b + 0} keys %asr_by_subshot_id;
  my $max_subshot_id = $subshot_sorted_ids[scalar(@subshot_sorted_ids) - 1];
  my $min_subshot_id = $subshot_sorted_ids[0];

  foreach my $subshot_id (@subshot_sorted_ids) {
    my $subshot_window_start = $subshot_id - (($sliding_window - 1) / 2) + $window_right_shift - $window_left_shift;
    my $subshot_window_end = $subshot_id + (($sliding_window - 1) / 2) + $window_right_shift - $window_left_shift;

    $subshot_window_start = $min_subshot_id if ($subshot_window_start <= $min_subshot_id);
    $subshot_window_end = $max_subshot_id if ($subshot_window_end >= $max_subshot_id);
print "$subshot_window_start $subshot_window_end\n";

    my @combined_asr = '';
    foreach ($subshot_window_start..$subshot_window_end) {
      push @combined_asr, $asr_by_subshot_id{$_}; 
    }
    my $raw_index_asr = join ' ', @combined_asr;
    my @index_asr;

    my %history_asr;
    foreach (split ' ', $raw_index_asr) {
      if (!defined $history_asr{$_}) {
        push @index_asr, $_;
        $history_asr{$_} = 1;
      }
    }
    
    my $index_asr = join ' ', @index_asr;
    
    print "indexing subshot id: $subshot_id\n";

    $doc .=<<END;
<DOC>
<DOCNO>$subshot_id</DOCNO>
<TEXT>
$index_asr
</TEXT>
</DOC>
END

    if (length($doc) >= 10000000) {
      $doc >> io($output_filename); 
      $doc = '';
    } 
  }

  if ($doc ne '') {
    $doc >> io($output_filename);
    $doc = '';
  }
}

exit;

sub round {
    my($number) = shift;
    return int($number + .5);
}

sub trim($)
{
	my $string = shift;
	$string =~ s/^\s+//;
	$string =~ s/\s+$//;
	return $string;
}
# Left trim function to remove leading whitespace
sub ltrim($)
{
	my $string = shift;
	$string =~ s/^\s+//;
	return $string;
}
# Right trim function to remove trailing whitespace
sub rtrim($)
{
	my $string = shift;
	$string =~ s/\s+$//;
	return $string;
}
