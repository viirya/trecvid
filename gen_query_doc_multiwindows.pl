
use Search::FreeText;
use IO::All;
use Data::Dumper;
use Lingua::Stem qw(stem);
use Lingua::StopWords qw(getStopWords);
use Getopt::Long;


my @slidings;
#my $output_filename;
my $tv_year = 'tv05';
my $index_dir_base = '/Users/viirya/Research/search/lemur_test/';
my $result_count = 3000;

GetOptions ("idx=s" => \@slidings, "y=s" => \$tv_year, "idx_base=s" => \$index_dir, "rs=i" => \$result_count); #, "o=s" => \$output_filename);

my $stopwords = getStopWords('en');

my $year;
$year = '2005' if ($tv_year eq 'tv05');
$year = '2006' if ($tv_year eq 'tv06');
$year = '2007' if ($tv_year eq 'tv07');
$year = '2008' if ($tv_year eq 'tv08');

print "generating lemur query document for $tv_year\n";

my %subshot_rank;

my $raw_queries = io("$tv_year/topics$year.txt");
my %queries;

while (my $line = $raw_queries->getline) {
  if ($line =~ m/(\d*)\s*Find shots of (.*)/ || $line =~ m/(\d*)\s*Find shots with (.*)/ || $line =~ m/(\d*)\s*Find shots that (.*)/ || $line =~ m/(\d*)\s*Find (.*)/) {
    $queries{$1} = $2;
  }
}

foreach (@slidings) {
  my ($index_dir, $weight) = split(/,/, $_);

  print "searching $index_dir with weight: $weight\n";

  my $index = '<index>' . $index_dir_base . $index_dir . '</index>';
  my $count = 0;
  foreach $topic_id (keys %queries) {
     print "search for: $topic_id.\n";
#next if $topic_id ne '0149';
#last if $count++ > 2;
     my $query = $queries{$topic_id};
     my @query = split ' ', $query;

     my @removed_stopwords = grep { !$stopwords->{$_} } @query;
     foreach (0..scalar(@removed_stopwords)-1) {
       $removed_stopwords[$_] =~ s/(.*)\,(.*)/$1$2/;
       $removed_stopwords[$_] =~ s/(.*)\-(.*)/$1$2/;
       $removed_stopwords[$_] =~ s/(.*)\.(.*)/$1$2/;
       $removed_stopwords[$_] =~ s/(.*)\'(.*)/$1$2/;
       $removed_stopwords[$_] =~ s/(.*)\((.*)/$1$2/;
       $removed_stopwords[$_] =~ s/(.*)\)(.*)/$1$2/;
       $removed_stopwords[$_] =~ s/(.*)\/(.*)/$1$2/;
     }

     $query = join ' ', @removed_stopwords;

     my $query_parameter =<<END;
<parameters>
    $index
    <textQuery>/Users/viirya/Research/search/lemur_test/query_text_$tv_year.txt</textQuery>
    <resultFile>/Users/viirya/Research/search/lemur_test/search_result_$tv_year.txt</resultFile>
    <resultCount>$result_count</resultCount>
    <feedbackDocCount>1000</feedbackDocCount>
    <feedbackTermCount>200</feedbackTermCount>
    <retModel>okapi</retModel>
    <BM25K1>1.2</BM25K1>
    <BM25B>0.75</BM25B>
    <BM25K3>7</BM25K3>
    <BM25QTF>0.5</BM25QTF>
</parameters>
END

     my $query_file = "/Users/viirya/Research/search/lemur_test/query_$tv_year.txt";
     $query_parameter > io($query_file);

     my $query_text =<<END;
<DOC 1>
$query
</DOC>
END

     my $query_text_file = "/Users/viirya/Research/search/lemur_test/query_text_$tv_year.txt";
     $query_text > io($query_text_file);

     my $output = `RetEval $query_file 2>/dev/null`;

     my $result_file = "/Users/viirya/Research/search/lemur_test/search_result_$tv_year.txt";
     $output < io($result_file);

     my @raw_ranked_list = split "\n", $output;
     my $sum_of_score = 0;
     my %subshot_rank_iteration;

     my $max_score = 0;
     my $min_score = 100000000;
     my $counter = 0;
     foreach (@raw_ranked_list) {
       if ($_ =~ m/(.*?)\s(.*?)\s(.*?)\s(.*?)\s(.*?)\s(.*)/) {
         my $subshot_id = $3;
         my $score = $5;

         $subshot_rank_iteration{$subshot_id} += $score;
         $sum_of_score += $score;
         $max_score = $score if $score > $max_score;
         $min_score = $score if $score < $min_score;
         $counter++;
       } 
     }

     my $mean = $sum_of_score / $counter;
     my $std = 0;
     foreach (keys %subshot_rank_iteration) {
       $std += ($subshot_rank_iteration{$_} - $mean) ** 2;
     }
     $std = $std / $counter;
     $std = sqrt($std);

     foreach (keys %subshot_rank_iteration) {
       $subshot_rank_iteration{$_} = ($subshot_rank_iteration{$_} - $mean) / $std;
       $subshot_rank_iteration{$_} = 1 / (1 + exp(-($subshot_rank_iteration{$_})));
       $subshot_rank{$topic_id}{$_} += ($weight * $subshot_rank_iteration{$_});
     }

  }
}

foreach $topic_id (keys %queries) {

  my @subshot_sorted_ids = sort { $subshot_rank{$topic_id}{$a} <=> $subshot_rank{$topic_id}{$b} } keys %{$subshot_rank{$topic_id}};

  @subshot_sorted_ids = reverse @subshot_sorted_ids;
  
  unlink("$tv_year/asr_mt_similarity/" . $topic_id . '.txt');

  my $ranked_list = join "\n", @subshot_sorted_ids[0..($result_count-1)];
  $ranked_list >> io("$tv_year/asr_mt_similarity/" . $topic_id . '.txt');

  unlink("$tv_year/asr_mt_similarity/scores/" . $topic_id . '.txt');

  my @ranked_scores;
  foreach (@subshot_sorted_ids[0..($result_count-1)]) {
    push @ranked_scores, ($subshot_rank{$topic_id}{$_} / scalar(@slidings));
  }   
  my $ranked_scores = join "\n", @ranked_scores;
  $ranked_scores >> io("$tv_year/asr_mt_similarity/scores/" . $topic_id . '.txt');
}


exit;

sub get_synset_of_wordnet {

  my $querystring = shift;
  my $wordnet_dict = shift;

  my $wn = WordNet::QueryData->new($wordnet_dict);

  my @querystring_types = $wn->querySense($querystring, "syns");

  my @ret;
  foreach $type (@querystring_types) {
    my @meanings = $wn->querySense($type, "syns");
    foreach $meaning (@meanings) {
      my @syn = $wn->querySense($meaning, "syns");
      foreach $word (@syn) {
        if ($word =~ m/^(.*?)#.*/) {
          push @ret, $1;
        }
      }
    }
  }

  return \@ret;

}

