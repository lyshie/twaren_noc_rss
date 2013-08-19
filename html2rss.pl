#!/usr/bin/env perl
#===============================================================================
#
#         FILE: html2rss.pl
#
#        USAGE: ./html2rss.pl
#
#  DESCRIPTION: Convert TWAREN NOC Bulletin Board to RSS/Atom
#
#      OPTIONS: ---
# REQUIREMENTS: ---
#         BUGS: ---
#        NOTES: ---
#       AUTHOR: SHIE, Li-Yi <lyshie@mx.nthu.edu.tw>
# ORGANIZATION:
#      VERSION: 1.0
#      CREATED: 2013.03.01 13:35:27
#     REVISION: ---
#===============================================================================

use strict;
use warnings;

use FindBin qw($RealBin);
use File::stat;
use LWP::UserAgent;              # fetch content from web
use Mojo::DOM;                   # parse HTML into DOM tree
use XML::RSS;
use Digest::MD5 qw(md5_hex);     # unique temp filename
use Encode qw(encode decode);    # handle wide-character
use HTML::Entities;              # insert HTML content into description
use POSIX qw(strftime);          # compatible for RFC-822 date-time format
use Date::Parse;

my $BOARD_FILE    = "$RealBin/cache/noc_board.txt";
my $NOC_BOARD_URL = 'http://noc.twaren.net/noc_2008/NOCBulletin/index.php';
my $NOC_BASE_URL  = 'http://noc.twaren.net';

my $RSS_FILE = "$RealBin/cache/noc_board.xml";

sub _fetch_content_from_remote {
    my ($url) = @_;

    my $content = '';

    my $ua = LWP::UserAgent->new();
    $ua->timeout(10);
    my $response = $ua->get($url);

    if ( $response->is_success() ) {
        $content = $response->content();
    }
    else {
        warn( $response->status_line() );
    }

    return $content;
}

sub get_content {
    my ( $filename, $url, $expire_time ) = @_;

    $expire_time = 3600 unless ($expire_time);

    my $content = '';

    if ( !-f $filename ) {
        $content = _fetch_content_from_remote($url);
        open( FH, ">", $filename );
        print FH $content;
        close(FH);
    }
    else {
        if ( time() - stat($filename)->ctime() > $expire_time ) {
            $content = _fetch_content_from_remote($url);
            open( FH, ">", $filename );
            print FH $content;
            close(FH);
        }
        else {
            open( FH, "<", $filename );
            local $/;
            $content = <FH>;
            close(FH);
        }
    }

    return $content;
}

# lyshie_20130301: generate RSS 2.0 file
sub create_rss_file {
    my @items = @_;

    my $rss = XML::RSS->new( version => '2.0', encode_output => 0, );

    $rss->channel(
        title   => 'TWAREN NOC 維運中心公告',
        link    => 'http://noc.twaren.net/noc_2008/NOCBulletin/',
        pubDate => strftime( "%a, %d %b %Y %H:%M:%S %z", localtime( time() ) ),
        lastBuildDate =>
          strftime( "%a, %d %b %Y %H:%M:%S %z", localtime( time() ) ),
        language => 'zh-tw',
    );

    foreach my $e (@items) {
        my $url      = $NOC_BASE_URL . $e->{'url'};
        my $filename = "$RealBin/cache/" . md5_hex($url) . ".temp";
        my $content  = get_content( $filename, $url );
        my $dom = Mojo::DOM->new->xml(0)->parse( decode( "utf-8", $content ) );

        my $html =
          $dom->find('div[class="content content-font"] table[border="1"]');

        $rss->add_item(
            title => encode( "utf-8", $e->{'title'} ),
            link  => $url,
            description =>
              encode_entities( encode( "utf-8", $html ), q{<>&'"} ),
            pubDate => strftime(
                "%a, %d %b %Y %H:%M:%S %z",
                localtime( str2time( ( $e->{'time'} ) ) )
            ),
        );
    }

    open( FH, ">", $RSS_FILE );
    print FH $rss->as_string;
    close(FH);
}

# main entry point
sub main {
    my $html = get_content( $BOARD_FILE, $NOC_BOARD_URL );
    my $dom = Mojo::DOM->new->xml(1)->parse( decode( "utf-8", $html ) );

    my @events = ();

    for my $e ( $dom->find('tr[class="content-hyperlink03"]')->each() ) {
        my %item = ();
        $item{'title'}      = encode_entities( $e->td->[1]->a->text );
        $item{'url'}        = $e->td->[1]->a->attr('href');
        $item{'board_type'} = $e->td->[2]->text;
        $item{'event_type'} = $e->td->[3]->text;
        $item{'time'}       = $e->td->[4]->text;

        push( @events, \%item );
    }

    create_rss_file(@events);
}

main;
