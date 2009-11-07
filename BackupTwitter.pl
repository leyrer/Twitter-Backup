#!/usr/bin/perl -w

use strict;
use FileHandle;

my $DEBUG          = 0;
my $twitter_module = "Net::Twitter";
my @twitter_fields =
  qw{ source favorited truncated created_at user in_reply_to_user_id id in_reply_to_status_id in_reply_to_screen_name text geo };

my %tweet_parm = (
    most_recent => 1,
    newest      => "",
    oldest      => "",
    max_return  => 200,
);
my $countimported = 0;
my $outfile;
my $tweets_returned = $tweet_parm{'max_return'};


if ( $#ARGV < 1 ) {
    die
"Please provide at least your Twitter username and password as command line arguments!\n";
}

print STDERR "Initialize Twitter connections ...\n" if ($DEBUG);

# Load Twitter-Module at runtime
eval "use $twitter_module";
die "couldn't load module $twitter_module. Reason: $!\n" if ($@);

# Initialize Twitter connections
my $nt = $twitter_module->new(
    traits   => [qw/API::REST/],
    username => $ARGV[0],
    password => $ARGV[1],
);
if ( not defined ($nt) or $@ ) {
    die "Could not create Twitter connection! " . $@ . "\n";
}

# Which user's Tweets should be stored? Default: logged in user
my $user2backup =
  ( defined ( $ARGV[2] ) and $ARGV[2] ne '' ) ? $ARGV[2] : $ARGV[0];

print STDERR "Get last fetched Tweet ...\n" if ($DEBUG);

# Get last fetched tweet, if possible
my $csv_file = $user2backup . "_twitter.csv";
if ( -f $csv_file ) {    # handle existing csv file
    $tweet_parm{'most_recent'} = get_most_recent_tweet($csv_file);
}

print STDERR "Open output file ...\n" if ($DEBUG);

# Open output CSV file
$outfile = &opencsv($csv_file);

print STDERR "Fetch & store Tweets ...\n" if ($DEBUG);
while ( $tweets_returned == $tweet_parm{'max_return'} ) {
    my $ratelimit = $nt->rate_limit_status();
    print "\nRemaining API calls: "
      . $ratelimit->{'remaining_hits'} . "/"
      . $ratelimit->{'hourly_limit'}
      . " (reset at "
      . $ratelimit->{'reset_time'} . ")\n"
      if ($DEBUG);

    my $statuses =
      &fetch_statuses_from_twitter( $user2backup, \%tweet_parm, $outfile );

    my $localcount = 0;
    for my $status (@$statuses) {
        $tweet_parm{'oldest'} = $status->{'id'};

        my @erglist = @$statuses;
        $tweets_returned = scalar @erglist;

        if ( $localcount == 0 and $tweet_parm{'oldest'} ne '' )
        {    # Don't add double entries in this 'edge' case
            $localcount++;
            next;
        }

        $localcount++;
        $countimported++;

        &writestatusmessage( $status, $outfile );
    } ## end for my $status (@$statuses)
    print "\t$localcount Tweets imported in this run.\n" if ($DEBUG);
    sleep (5) if ( $tweets_returned == $tweet_parm{'max_return'} );
} ## end while ( $tweets_returned ...)

$outfile->close;
print "All in all: $countimported Tweets stored.\n";

exit;


sub writestatusmessage {
    my ( $status, $fh ) = @_;

    # Code for CSV export
    my $csv = '';
    my $c   = 0;
    foreach my $f (@twitter_fields) {
        $csv .= "\t" if ( $c > 0 );
        my $t;
        if ( $f eq "user" ) {
            $t = $status->{$f}->{'id'};
        } else {
            $t = $status->{$f};
        }
        $t = "" if ( not defined $t );
        $t =~ s/(\n|\r)+/ /gs;    # remove newlines from Tweets
        $t =~ s/\t/    /g;        # replace tabs with four spaces in Tweets
        $csv .= '"' . $t . '"';
        $c++;
    } ## end foreach my $f (@twitter_fields)
    if ( not $outfile->print("$csv\n") ) {    # Write to csv file
        die "Couldn't write status to file! Reason: $!\n";
    }
} ## end sub writestatusmessage


sub fetch_statuses_from_twitter {
    my ( $user, $parm, $fh ) = @_;
    my $statuses;

    eval {

     # Handle multiple calls to user_timeline with different "start" Twitter-IDs
        if ( $parm->{'oldest'} eq '' and $parm->{'newest'} eq '' ) {
            $statuses = $nt->user_timeline(
                {
                    count    => $parm->{'max_return'},
                    since_id => $parm->{'most_recent'},
                    id       => $user,
                }
            );
        } else {
            $statuses = $nt->user_timeline(
                {
                    max_id   => $parm->{'oldest'},
                    count    => $parm->{'max_return'},
                    since_id => $parm->{'most_recent'},
                    id       => $user,
                }
            );
        } ## end else [ if ( $parm->{'oldest'}...)]
    };
    if ( my $err = $@ ) {    # errorhandling
        $fh->close;
        die $@ unless blessed $err && $err->isa('Net::Twitter::Error');
        die "HTTP Response Code: ", $err->code, "\n",
          "HTTP Message......: ", $err->message, "\n",
          "Twitter error.....: ", $err->error,   "\n";
    } ## end if ( my $err = $@ )
    return ($statuses);
} ## end sub fetch_statuses_from_twitter


sub opencsv {
    my ($filename) = @_;
    my $fh;

    if ( -f $csv_file ) {    # handle existing csv file
        $fh = new FileHandle ">> $filename";
        die "Couldn't open file '$filename' for writing! Reason: $!\n"
          if ( not defined $fh );
        $fh->binmode(":utf8");
    } else {                 # create new csv file
        $fh = new FileHandle ">> $filename";
        die "Couldn't open file '$filename' for writing! Reason: $!\n"
          if ( not defined $fh );
        $fh->binmode(":utf8");
        &print_csv_header();
    } ## end else [ if ( -f $csv_file ) ]
    return ($fh);
} ## end sub opencsv

sub get_most_recent_tweet {
    my ($filename) = @_;
    my $highest_id = 1;

    my $fh = new FileHandle "< $filename";
    die "Couldn't open file '$filename' for reading! Reason: $!\n"
      if ( not defined $fh );
    $fh->binmode(":utf8");
    $fh->getline();    # Skip the header-line

    my $line;
    while ( $line = $fh->getline() ) {
        chomp $line;
        my @data = split ( /\t/, $line );
        my $id = $data[6];
        $id =~ s/\"//g;
        $highest_id = $id if ( $highest_id eq '' or $id > $highest_id );
    } ## end while ( $line = $fh->getline...)
    $fh->close;
    return ($highest_id);
} ## end sub get_most_recent_tweet

sub print_csv_header {
    my ($fh) = @_;

    my $hc     = 0;
    my $header = '';
    foreach my $field (@twitter_fields) {
        $header .= "\t" if ( $hc > 0 );
        $header .= '"' . $field . '"';
        $hc++;
    }
    $fh->print("$header\n");
} ## end sub print_csv_header
