
use strict;
use XML::Simple;
use MediaTime;
use Data::Dumper;
use IO::All;
use Getopt::Long;
use POSIX qw(ceil floor);


my $asr_dir = '';
my $video_def = '';
my $mt_dir = '';
my $output_dir = '';
my $use = 'test';
my $year = '';

GetOptions ("video_df=s" => \$video_def, "asr_dir=s" => \$asr_dir, "mt_dir=s" => \$mt_dir, "output_dir=s" => \$output_dir, "use=s" => \$use, "year=s" => \$year);

print "$asr_dir $mt_dir\n";

if ($video_def eq '' || $asr_dir eq '' || $mt_dir eq '') {
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
  $clip_name =~ m/(.*)\.(mpg|MPG)/;
  my $video_name = $1;
  $collects{$vid}{'trecvid'} = $trecvid_video_id;
  $collects{$vid}{'video'} = $video_name;
}

#print Dumper(%collects);

foreach my $id (keys %collects) {
  next if !defined $collects{$id};

  my $trecvid_video_id = $collects{$id}{'trecvid'}; 
  my $video_name = $collects{$id}{'video'};

  print "processing $id in $video_def.....\n ";

  print $asr_dir . '/' . lc($video_name) . '.mp7.xml' . "\n";
  print $mt_dir . '/' . lc($video_name) . '.translation.xml' . "\n";

  next unless (-f $asr_dir . '/' . lc($video_name) . '.mp7.xml');
  next unless (-f $mt_dir . '/' . lc($video_name) . '.translation.xml');

  my $asr_xml = io($asr_dir . '/' . lc($video_name) . '.mp7.xml')->slurp;
  my $mt_xml = io($mt_dir . '/' . lc($video_name) . '.translation.xml')->slurp;

  $asr_xml =~ s/\&//g;
  $mt_xml =~ s/\&//g;

  my $asr_doc = $xs->XMLin($asr_xml);
  my $mt_doc = $xs->XMLin($mt_xml);

  #print Dumper($asr_doc->{Description}->[1]->{MultimediaContent}->{Audio}->{TemporalDecomposition}->{AudioSegment});

  #print Dumper($asr_doc->{Description}->[1]->{MultimediaContent}->{Audio}->{TemporalDecomposition}->{AudioSegment}->{'SPK17-003'}->{MediaTime});
#exit;

  my $speakers = $asr_doc->{Description}->[1]->{MultimediaContent}->{Audio}->{TemporalDecomposition}->{AudioSegment}; # = @{$asr_doc->{segments}->{speaker}};

  #if (ref() eq 'ARRAY') {
  #  @speakers = @{$asr_doc->{segments}->{speaker}};
  #}
  #else {
  #  push @speakers, $asr_doc->{segments}->{speaker};
  #}

  my @asr_mts; # = @{$mt_doc->{translation}};

  if (ref($mt_doc->{translation}) eq 'ARRAY') {
    @asr_mts = @{$mt_doc->{translation}};
  }
  else {
    push @asr_mts, $mt_doc->{translation};
  }

  my $mtp = MediaTime->new();

  my %speeches_time;
  foreach my $speaker (keys %{$speakers}) {
    my $label = $speaker;
    print "$label.....\n";

    my $mediatime = $speakers->{$label};

    my $begintime = $mtp->set_t_value($mediatime->{MediaTime}->{MediaTimePoint});
    my $duration = $mtp->set_pt_value($mediatime->{MediaTime}->{MediaDuration});
    my $endtime = $begintime + $duration;

    #print "$label: $begintime $endtime\n";

    $speeches_time{$label}{'begintime'} = $begintime;
    $speeches_time{$label}{'endtime'} = $endtime;
  }

  my $asr_content = '';
  foreach my $translation (@asr_mts) {
    my $content = $translation->{'content'};
    my $label = $translation->{'label'};

    my $begintime = $speeches_time{$label}{'begintime'};
    my $endtime = $speeches_time{$label}{'endtime'};
    my @content = split /\s/, $content;   

    foreach (@content) {
      my $string = $_;
      $string =~ s/\&//;
      next if $string eq '';
      $asr_content .= "$begintime\t$endtime\t$string\n";
    }
  }

  $asr_content > io($output_dir . '/' . $trecvid_video_id . '.tkn');

}

exit;

