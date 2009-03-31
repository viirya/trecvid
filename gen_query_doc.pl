
use Search::FreeText;
use IO::All;
use Data::Dumper;
use Lingua::Stem qw(stem);
use Lingua::StopWords qw(getStopWords);
use Getopt::Long;


my $tv_year = 'tv05';

GetOptions ("y=s" => \$tv_year);

my $stopwords = getStopWords('en');

my $year;

$year = '2005' if ($tv_year eq 'tv05');
$year = '2006' if ($tv_year eq 'tv06');
$year = '2007' if ($tv_year eq 'tv07');
$year = '2008' if ($tv_year eq 'tv08');

print "generating lemur query document for $tv_year\n";

my $raw_queries = io("$tv_year/topics$year.txt");
my %queries;

while (my $line = $raw_queries->getline) {
  if ($line =~ m/(\d*)\s*Find shots of (.*)/ || $line =~ m/(\d*)\s*Find shots with (.*)/ || $line =~ m/(\d*)\s*Find shots that (.*)/ || $line =~ m/(\d*)\s*Find (.*)/) {
    $queries{$1} = $2;
  }
}

foreach $topic_id (keys %queries) {
   print "search for: $topic_id.\n";

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
    <index>/Users/viirya/Research/search/lemur_test/index_$tv_year</index>
    <textQuery>/Users/viirya/Research/search/lemur_test/query_text_$tv_year.txt</textQuery>
    <resultFile>/Users/viirya/Research/search/lemur_test/search_result_$tv_year.txt</resultFile>
    <resultCount>3000</resultCount>
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

   unlink("$tv_year/asr_mt_similarity/" . $topic_id . '.txt');
   
   my @raw_ranked_list = split "\n", $output;
   my @ranked_list;

   foreach (@raw_ranked_list) {
     if ($_ =~ m/(.*?)\s(.*?)\s(.*?)\s(.*?)\s(.*?)\s(.*)/) {
       push @ranked_list, $3; 
     } 
   }

   my $ranked_list = join "\n", @ranked_list;
   $ranked_list >> io("$tv_year/asr_mt_similarity/" . $topic_id . '.txt'); 
};

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

