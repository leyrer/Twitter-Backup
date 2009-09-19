#!/usr/bin/perl -w

use strict;

my @twitter_fields = qw{ source favorited truncated created_at text user in_reply_to_user_id id in_reply_to_status_id in_reply_to_screen_name};

if( $#ARGV < 1) {
	die "Please provide at least your Twitter username and password als command line arguments!\n";
}


# Load Twitter-Module at runtime
my $twitter_module = "Net::Twitter";
eval "use $twitter_module";
die "couldn't load module : $!n" if ($@);

# Initialize Twitter connections
my $nt = $twitter_module->new(
	traits   => [qw/API::REST/],
	username => $ARGV[0],
	password => $ARGV[1],
);
if( not defined($nt) or $@ ) {
	die "Could not create Twitter connection! " . $@ . "\n";
}

# Which user's Tweets should be backuped? Default: logged in user
my $user2backup = (defined($ARGV[2]) and $ARGV[2] ne '') ? $ARGV[2] : $ARGV[0];


# Open output CSV file
open(CSV, ">" . $user2backup . "_twitter.csv") or die "Write error '" .$user2backup . "_twitter.csv'! $!\n";
binmode CSV, ":utf8";
my $hc = 0;
my $header = '';
foreach my $field (@twitter_fields) {
	$header .= "\t" if ($hc > 0);
	$header .= '"' . $field . '"';
	$hc++;
}
print CSV "$header\n";

my $lastid = '';
my $returns = 200;
my $countimported = 0;

while ($returns == 200) {
	my $ratelimit = $nt->rate_limit_status();
	print "\nRemaining API calls: " . $ratelimit->{'remaining_hits'} . "/" . $ratelimit->{'hourly_limit'} . " (reset at " . $ratelimit->{'reset_time'} . ")\n";
	eval {
		my $statuses;
		my $localcount = 0;
		# Handle multiple calls to user_timeline with different "start" Twitter-IDs
		if( $lastid eq '') {
			$statuses = $nt->user_timeline({ count => 200, id=> $user2backup });
		} else {
			$statuses = $nt->user_timeline({ max_id => $lastid, count => 200, id => $user2backup });
		}
		my @erglist = @$statuses;
		$returns = scalar @erglist;
	
		for my $status ( @$statuses ) {
			$lastid = $status->{'id'};
			if( $localcount == 0 and $lastid ne '') { # Don't add double entries
				$localcount++;
				next;
			}
			$localcount++;
			$countimported++;
			my $csv = '';
			my $c = 0;
			foreach my $f (@twitter_fields) {
				$csv .= "\t" if ($c > 0);
				my $t;
				if( $f eq "user") {
					$t = $status->{$f}->{'id'};
				} else {
					$t = $status->{$f};
				}
				$t = "" if (not defined $t);
				$csv .= '"' . $t . '"';
				$c++;
			}
			print CSV "$csv\n"; 
		}
		print "\t$localcount Tweets imported in this run.\n"; 
	};

	if ( my $err = $@ ) { # errorhandling
		close(CSV);
		print "All in all: $countimported Tweets stored.\n";
		die $@ unless blessed $err && $err->isa('Net::Twitter::Error');

		die "HTTP Response Code: ", $err->code, "\n",
			"HTTP Message......: ", $err->message, "\n",
			"Twitter error.....: ", $err->error, "\n";
	}
	print "Sleeping 5 seconds (just in case) ...\n";
	sleep(5);
}

close(CSV);
print "All in all: $countimported Tweets stored.\n";

