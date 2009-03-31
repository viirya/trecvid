
use Search::FreeText;
use IO::All;
use Data::Dumper;
use Lingua::Stem qw(stem);
use Lingua::StopWords qw(getStopWords);
use WWW::Wikipedia;
use Lingua::EN::Keywords;
use Search::FreeText::LexicalAnalysis;
use REST::Google::Search;
use AI::Categorizer::FeatureVector;


my $lexicalizer = new Search::FreeText::LexicalAnalysis 
     (-filters => [ qw(Search::FreeText::LexicalAnalysis::Heuristics
                       Search::FreeText::LexicalAnalysis::Tokenize
                       Search::FreeText::LexicalAnalysis::Stop) ]);
                       #Search::FreeText::LexicalAnalysis::Stem) ]);

my $stopwords = getStopWords('en');

my $tv_year = $ARGV[0] || 'tv05';
my $year;
print "generating lemur query document for $tv_year\n";
$year = '2005' if ($tv_year eq 'tv05');
$year = '2006' if ($tv_year eq 'tv06');

my $raw_queries = io("$tv_year/topics$year.txt");
my %queries;

while (my $line = $raw_queries->getline) {
  if ($line =~ m/(\d*)\s*Find shots of (.*)/ || $line =~ m/(\d*)\s*Find shots with (.*)/) {
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

   my @dup_removed_stopwords = @removed_stopwords;
   my %history;

   my %expansion_keywords;
   #$expansion_keywords{$_} = 1 foreach @removed_stopwords;

   my $dup_query = $query;
   foreach (@dup_removed_stopwords) {
     next if ($_ =~ m/^[a-z]/);
     #my $freq = get_frequent_words_from_wikipedia([$_]);
     #$expansion_keywords{$_} = 1 foreach @{$freq};
     next if $_ eq '';

     my $ret = get_related_words_from_wikipedia($_);
     print "There are wikipedia words related to $_ in query:\n";
     #print Dumper($ret);

     foreach (@{$ret}) {
       next if defined $history{$_};
       $history{$_} = 1;
       #$expansion_keywords{$_} = 1;
       #next;

       if ($dup_query =~ m/$_/ && $_ ne '') {
         print "The wikipedia word $_ is related to query\n"; 
         $dup_query .= ' ' . $_;
         #my $freq = get_frequent_words_from_wikipedia([$_]);
         my $freq = get_related_words_from_wikipedia($_);
         $expansion_keywords{$_} = 1 foreach @{$freq};
         #push @removed_stopwords, @{$freq};
       }

     }
   }
   $query .= ' ' . join ' ', keys %expansion_keywords; #@removed_stopwords;

print "query: $query\n";
next;
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

sub get_frequent_words_from_wikipedia {

  my $queries = shift;
  my $wiki = WWW::Wikipedia->new();
  my @ret;

  my $stopwords = getStopWords('en');

  foreach my $query (@{$queries}) {
    next if $query eq '';

    print "search wikipedia for $query\n";

    my $wiki_result = $wiki->search($query);
    next if (!defined $wiki_result);

    my $wiki_text = $wiki_result->text;
    $wiki_text =~ s/\{\{Infobox.*\}\}(.*)/$1/s;
    $wiki_text =~ s/:.*?\n//g;
    $wiki_text =~ s/<ref>.*?<\/ref>//sg;

    my $words = $lexicalizer->process($wiki_result->text);

    my @raw_keywords = split ' ', $wiki_text;
    my @keywords;
    
    foreach (@raw_keywords) {
      $_ =~ s/(\W*)(\w*)(\W*)/$2/g;
      $_ =~ s/(.*)\,(.*)/$1$2/;
      $_ =~ s/(.*)\-(.*)/$1$2/;
      $_ =~ s/(.*)\.(.*)/$1$2/;
      $_ =~ s/(.*)\'(.*)/$1$2/;
      $_ =~ s/(.*)\((.*)/$1$2/;
      $_ =~ s/(.*)\)(.*)/$1$2/;
      $_ =~ s/(.*)\/(.*)/$1$2/;
      $_ =~ s/(.*)\>(.*)/$1$2/;
      $_ =~ s/(.*)\<(.*)/$1$2/;
      $_ =~ s/(\W*)//g;
      $_ =~ s/(\d*)//g;
      push @keywords, $_;
    }

    @keywords = grep { !$stopwords->{lc($_)} } @keywords;
    push @ret, @keywords;
    #push @ret, @{$words};
    next;

    my %keyword_hash;
    foreach my $keyword (@keywords) {
      $keyword_hash{$keyword}++ if $keyword ne '';
    }
 
    my @sorted_keywords = sort {$keyword_hash{$a} <=> $keyword_hash{$b}} keys %keyword_hash;
    
    my $max_index = scalar(@sorted_keywords) - 1;
    my $min_index = scalar(@sorted_keywords) - 6;

    $min_index = 0 if $min_index < 0;
#print Dumper(@sorted_keywords[$min_index..$max_index]);
    push @ret, @sorted_keywords[$min_index..$max_index];
  }

  return \@ret;

}

sub get_related_words_from_wikipedia {

  my $query = shift;
  my $wiki = WWW::Wikipedia->new();
  my @raw_ret;
  my @ret;

  my $wiki_result = $wiki->search($query);
  next if (!defined $wiki_result);

  my $words = $lexicalizer->process($wiki_result->text);

  my @possible_entries;

  @raw_ret = $wiki_result->related();
  foreach (@raw_ret) {
    $_ =~ s/(.*)\,(.*)/$1$2/;
    $_ =~ s/(.*)\-(.*)/$1$2/;
    $_ =~ s/(.*)\.(.*)/$1$2/;
    $_ =~ s/(.*)\'(.*)/$1$2/;
    $_ =~ s/(.*)\((.*)/$1$2/;
    $_ =~ s/(.*)\)(.*)/$1$2/;
    $_ =~ s/(.*)\/(.*)/$1$2/;
    $_ =~ s/(.*)\>(.*)/$1$2/;
    $_ =~ s/(.*)\<(.*)/$1$2/;
    push @possible_entries, $_;
  }

  @ret = @possible_entries;
  
  my %similarities;
  my $count = 0;
  foreach (@possible_entries) {
    last if $count++ > 20;
    my $sim = get_google_sim(($query, $_));
    print "similarity between $query and $_: $sim\n";
    $similarities{$_} = $sim;
  }

  my @sorted_keys = sort {$similarities{$a} <=> $similarities{$b}} keys %similarities;
  
  my $max_index = scalar(@sorted_keys) - 1;
  my $min_index = scalar(@sorted_keys) / 2;

  @ret = @sorted_keys[$min_index..$max_index];
  print Dumper(@ret);




  #my %history;
  #my $count = 0;
  #foreach (@possible_entries) { 
  #  my $entry = $_;
  #  next if defined $history{$entry};
  #  $history{$entry} = 1;
  #  last if $count++ >= 10;
#print "query wikipedia for $entry.....\n";
  #  my $wiki_result = $wiki->search($entry);
  #  next if (!defined $wiki_result);

  #  my $text = $wiki_result->text;

  #  if ($text =~ m/$query/) {
  #    print "wikipedia entry $entry related to query $query.\n";
  #    push @ret, $entry;
  #  }
  #}

  #@ret = @{$words};
  #@ret = @ret[0..10];
  
  return \@ret;

}


sub get_google_sim($) {

my %keywordset;
my %results;
my %counts;
#my $query_terms = shift;
my @queries = (shift, shift);
my @queries_counts = ($queries[0], $queries[1], $queries[0] . ' ' . $queries[1]);

REST::Google::Search->http_referer('http://example.com');

foreach $query (@queries_counts) {
  #print $query . "\n";
  my $res = REST::Google::Search->new(
        q => $query
  );

  #die "response status failure" if $res->responseStatus != 200;
  while ($res->responseStatus != 200) {
    $res = REST::Google::Search->new(
        q => $query
    );    
    sleep 1;
  }

  my $data = $res->responseData;

  my $cursor = $data->cursor;

  #printf "pages: %s\n", $cursor->pages;
  #printf "current page index: %s\n", $cursor->currentPageIndex;
  #printf "estimated result count: %s\n", $cursor->estimatedResultCount;
  
  #$results{$query} = \$data->results; 
  my @search_ret = $data->results;
  $results{$query} = \@search_ret;
  $counts{$query} = $cursor->estimatedResultCount;
  #foreach $r ($data->results) {
  #  print Dumper($r);
  #  push @{$results{$query}}, $r;
  #}
  #print Dumper(@{$results{$query}});
}

my $stemmer = Lingua::Stem->new(-locale => 'EN-US');
$stemmer->stem_caching({ -level => 2 });
$stemmer->add_exceptions({ 'programmer' => 'program' });

my $stopwords = getStopWords('en');

foreach $query (@queries) {
  foreach my $r (@{$results{$query}}) {
    my $content = $r->content;
    my @keywords = keywords($content); 
    my @split_keywords;

    foreach $keyword (@keywords) {
      my @sub_keywords = split(/\s/, $keyword);
      push @split_keywords, @sub_keywords;  
    }
    for $i (0..scalar(@split_keywords)-1) {
      my $string = $split_keywords[$i];
      $string =~ s/^\s+//;
      $string =~ s/\s+$//;
      $split_keywords[$i] = $string if ($string =~ m/(\w*)/);
    }
    my @removed_stop_keywords = grep { !$stopwords->{$_} } @split_keywords;  
    my $stemmmed_keywords   = $stemmer->stem(@removed_stop_keywords);
    #my $stemmmed_keywords   = \@removed_stop_keywords;

    #print "keywords for " . $r->url . "\n";

    foreach $keyword (@{$stemmmed_keywords}) {
      next if ($keyword eq '' || ($keyword =~ m/(\d|!)/));
      #print "keyword: $keyword\n"; 
      if (!defined $keywordset{$query}{$keyword}) {
        $keywordset{$query}{$keyword} = 1;
      }
      else {
        $keywordset{$query}{$keyword}++;
      }
    }
  }
}

foreach $query (@queries) {
  foreach $keyword (keys %{$keywordset{$query}}) {
    foreach $sec_query (@queries) {
      next if $sec_query eq $query;
      if (!defined $keywordset{$sec_query}{$keyword}) {
        $keywordset{$sec_query}{$keyword} = 0;
      }
      if ($keywordset{$query}{$keyword} == 0 && $keywordset{$sec_query}{$keyword} == 0) {
        undef $keywordset{$query}{$keyword};
        undef $keywordset{$sec_query}{$keyword};
      }
    }
  }
}

my @feature_vectors;

foreach $query (@queries) {
  #print Dumper(%{$keywordset{$query}});
  my $f = new AI::Categorizer::FeatureVector (features => $keywordset{$query});
  #print "$_ feature length: " . $f->length . "\n";
  #$f->normalize;
  push @feature_vectors, $f;
}

my $vector_dot = $feature_vectors[0]->dot($feature_vectors[1]);

my $vector_abs1 = 0;
my $vector_abs2 = 0;
my $vector_norm = 0;

foreach $feature ($feature_vectors[0]->names) {
  $vector_abs1 += ($feature_vectors[0]->value($feature) ** 2);
}
foreach $feature ($feature_vectors[1]->names) {
  $vector_abs2 += ($feature_vectors[1]->value($feature) ** 2);
}
$vector_norm = sqrt($vector_abs1) * sqrt($vector_abs2);

my $cosine;

$cosine = $vector_dot / $vector_norm if $vector_norm != 0;
$cosine = 0 if $vector_norm == 0;

#print "dot: $vector_dot, norm: $vector_norm, cosine: $cosine\n";


my ($n1, $n2, $n3, $total) = (0, 0, 0, 0);
my $similarity;

$n1 = $counts{$queries_counts[0]} > 0 ? log($counts{$queries_counts[0]}) : 1;
$n2 = $counts{$queries_counts[1]} > 0 ? log($counts{$queries_counts[1]}) : 1;
$n3 = $counts{$queries_counts[2]} > 0 ? log($counts{$queries_counts[2]}) : 1;

$n1 = 1 if $n1 <= 0;
$n2 = 1 if $n2 <= 0;
$n3 = 1 if $n3 <= 0;

$similarity = ($n3 / ($n1 * $n2));
#print "Word similarity: $similarity\n";

my $alpha = 0.5;
my $weighted_sim = 0;

$weighted_sim = $alpha * $cosine + (1 - $alpha) * $similarity;
#print "Weighted similarity: $weighted_sim\n";

return $weighted_sim;

}
