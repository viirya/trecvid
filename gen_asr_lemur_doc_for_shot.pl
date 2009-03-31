
use strict;
use Search::FreeText;
use IO::All;
use Data::Dumper;
use Lingua::Stem qw(stem);
use Lingua::StopWords qw(getStopWords);
use Getopt::Long;
use XML::Simple;

my $tv_year = 'tv05';
my $sliding_window = 5;
my $window_right_shift = 0;
my $window_left_shift = 0;
my $video_def;
my $use = 'test';
my $msb_dir = '';
my $shot_mapping_file = '';

GetOptions ("video_def=s" => \$video_def, "y=s" => \$tv_year, "w=i" => \$sliding_window, "rs=i" => \$window_right_shift, "ls=i" => \$window_left_shift, "use=s" => \$use, "msb_dir=s" => \$msb_dir, "shot_mapping=s" => \$shot_mapping_file);

my $stemmer = Lingua::Stem->new(-locale => 'EN-US');

$stemmer->stem_caching({ -level => 2 });
$stemmer->add_exceptions({ 'programmer' => 'program' });

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

my %number_of_shots;
my %video_shots;
my $shot_mapping = io($shot_mapping_file);
while (my $mapping_line = $shot_mapping->getline) {
  my $video_id;
  my $shot_id;
  my $shot_label;
  if ($mapping_line =~ m/(.*?)\s(.*?)\s(.*)/) {
    $video_id = $1;
    $shot_id = $2;
    $shot_label = $3;

    $video_shots{$video_id}{$shot_id} = $shot_label;

    $number_of_shots{$video_id}{'max'} = ($2 + 0) if ($2 + 0) > $number_of_shots{$video_id}{'max'} || !defined $number_of_shots{$video_id}{'max'};
    $number_of_shots{$video_id}{'min'} = ($2 + 0) if ($2 + 0) < $number_of_shots{$video_id}{'min'} || !defined $number_of_shots{$video_id}{'min'};
  }
  else {
    next;
  }
}

my $doc = '';

# to obtain the mapping of frame to shot id for every videos.
my %shots;
my @master_shot_ref_files = io($msb_dir);

foreach my $video_id (sort {$a + 0 <=> $b + 0; } keys %collects) {
  next unless defined($collects{$video_id});

  my $video_name = $collects{$video_id}{'video'};
  my $master_shot_ref_file = $video_name . ".msb";

  my $master_shot_ref = io($msb_dir . '/' . $master_shot_ref_file);

  my $shot_count = 0;
  while (my $shot_line = $master_shot_ref->getline) {
    if ($shot_line =~ m/^(\d*?)\s(\d*)/) {

      my $start_frame = $1;
      my $end_frame = $2;

      my @video_shots = sort {$a + 0 <=> $b + 0; } keys %{$video_shots{$video_id}}; 
      $shots{$video_id}{$start_frame} = $video_shots[$shot_count];
      $shot_count++;
    }
  }
}

my $stopwords = getStopWords('en');
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

  # kframes: used as mapping of frame to keyframe id
  my %kframes;

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

    if ($year eq '2005' || $year eq '2006') {
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

#print Dumper(%asr_by_frame); 

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

  #print Dumper(@sorted_frame);

  my %asr_by_shot_id;
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

    my $frame_located_start = 0;
    my $frame_located_end = 0;
    my $mode = 0;
    foreach my $shot_frame_start (sort {$a + 0 <=> $b + 0} keys %{$shots{$video_id}}) {
      if ($mode == 0) {
        if ($shot_frame_start <= $frame_num_start) {
          $frame_located_start = $shot_frame_start;
          $frame_located_end = $shot_frame_start;
          next;
        }
        else {
          $mode = 1;
        }
      }
      if ($mode == 1) {
        if ($shot_frame_start <= $frame_num_end) {
          $frame_located_end = $shot_frame_start;
          next;
        }
        else {
          #$kframe_located_end = $kframe_start;
          last;
        }
      }
    }
   
    #if ($frames eq '599-1499' || $frames eq '120-569') {
    #  print "$frame_num_start $frame_num_end\n";
    #  print "$kframe_located_start $kframe_located_end\n";
    #}

    $frame_located_start += 0;
    $frame_located_end += 0;

#print "$frame_num_start $frame_num_end\n";
#print "$frame_located_start $frame_located_end\n";

    #my $kframe_id_start = $kframes{$kframe_located_start} + 0;
    #my $kframe_id_end = $kframes{$kframe_located_end} + 0;

#print "$kframe_id_start $kframe_id_end\n"; 

    #my $subshot_start = $subshots{$video_id}{$kframe_id_start};
    #my $subshot_end = $subshots{$video_id}{$kframe_id_end};
   
    my $shot_start = $shots{$video_id}{$frame_located_start};
    my $shot_end = $shots{$video_id}{$frame_located_end}; 

    print "shot: $shot_start to $shot_end\n";

    #if ($subshot_end == 444) {
    #print "$frame_num_start $frame_num_end\n"; #0-180
    #print "$kframe_located_start $kframe_located_end\n"; #0-225
    #print "$video_id $kframe_id_start to $kframe_id_end\n"; #0-276
    #}

    my $asr = $asr_by_frame{$frames};

#print Dumper($asr);
#print "$frames:";
#print Dumper($asr_by_frame{$frames});
    #print Dumper($asr);

    my $asr_length = scalar(@{$asr});
    my $shot_index = $shot_start;

    my %cache_of_asr;
    my $overlap = 0;
    foreach (0..($shot_end - $shot_start)) {
      my $start_index = $asr_length / ($shot_end - $shot_start + 1) * $_;
      my $end_index = $asr_length / ($shot_end - $shot_start + 1) * ($_ + 1) - 1;

      $start_index = $asr_length - 1 if ($start_index >= $asr_length);
      $end_index = $asr_length - 1 if ($end_index >= $asr_length);

      my @asr_of_shot;
      foreach ($start_index..$end_index) {
        push @asr_of_shot, $asr->[$_]; 
      }

      my %asr_hash;

      foreach (@asr_of_shot) {
        $asr_hash{trim($_)} = 1;
      }
      
      if (defined $asr_by_shot_id{$shot_index + $_}) {
        my @dup_asr_of_shot = split ' ', $asr_by_shot_id{$shot_index + $_};
          foreach (@dup_asr_of_shot) {
            if (defined $asr_hash{trim($_)}) {
              undef $asr_hash{trim($_)};
              $overlap = 1;
            }
          }
      } 

      if ($overlap == 1) {
        $cache_of_asr{$shot_index + $_ + 1} = join ' ', @asr_of_shot;
      }

      foreach (0..scalar(@asr_of_shot)-1) {
        if (!defined $asr_hash{trim($asr_of_shot[$_])}) {
          delete $asr_of_shot[$_];
        }    
      }

      #my $stemmed_asr = $stemmer->stem(@asr_of_subshot);
      #$asr_by_subshot_id{$subshot_index + $_} = join ' ', @{$stemmed_asr};

      my @removed_stop_keywords_asr_mt = grep { !$stopwords->{$_} } @asr_of_shot;
      $asr_by_shot_id{$shot_index + $_} .= ' ' . join ' ', @removed_stop_keywords_asr_mt; # . ' ' . $asr_by_subshot_id{$subshot_index + $_}; 


      #if ($overlap == 2) {
      if (defined $cache_of_asr{$shot_index + $_} && $cache_of_asr{$shot_index + $_} ne '') {
        $asr_by_shot_id{$shot_index + $_} .= ' ' . $cache_of_asr{$shot_index + $_};
        $cache_of_asr{$shot_index + $_} = '';
        #$asr_by_subshot_id{$subshot_index + $_} .= ' ' . join ' ', @cache_of_asr; #  $asr_by_subshot_id{$subshot_index + $_}; 
        $overlap = 0;
      }
      $overlap = 0 if $overlap == 1;

    }
    #print Dumper(%asr_by_shot_id);
  }
#print Dumper(%asr_by_subshot_id);

  foreach ($number_of_shots{$video_id}{'min'}..$number_of_shots{$video_id}{'max'}) {
    if (!defined $asr_by_shot_id{$_}) {
      $asr_by_shot_id{$_} = '';
    }
  }

print Dumper(%asr_by_shot_id);

  my @shot_sorted_ids = sort {$a + 0 <=> $b + 0} keys %asr_by_shot_id;
  my $max_shot_id = $shot_sorted_ids[scalar(@shot_sorted_ids) - 1];
  my $min_shot_id = $shot_sorted_ids[0];

  foreach my $shot_id (@shot_sorted_ids) {

#print "shot: $shot_id asr: " . $asr_by_shot_id{$shot_id} . "\n";

    my $shot_window_start = $shot_id - (($sliding_window - 1) / 2) + $window_right_shift - $window_left_shift;
    my $shot_window_end = $shot_id + (($sliding_window - 1) / 2) + $window_right_shift - $window_left_shift;

    $shot_window_start = $min_shot_id if ($shot_window_start <= $min_shot_id);
    $shot_window_end = $max_shot_id if ($shot_window_end >= $max_shot_id);

print "$shot_window_start $shot_window_end\n";

    my @combined_asr = '';
    foreach ($shot_window_start..$shot_window_end) {
      push @combined_asr, $asr_by_shot_id{$_}; 
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
    
#print "subshot id: $subshot_id, asr: $index_asr\n";
    print "indexing shot id: $shot_id\n";
   
    my $shot_label = $video_shots{$video_id}{$shot_id};

    $doc .=<<END;
<DOC>
<DOCNO>$shot_label</DOCNO>
<TEXT>
$index_asr
</TEXT>
</DOC>
END

    if (length($doc) >= 10000000) {
      $doc >> io("lemur_test/$tv_year.txt");
      $doc = '';
    } 
  }

  if ($doc ne '') {
    $doc >> io("lemur_test/$tv_year.txt");
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
