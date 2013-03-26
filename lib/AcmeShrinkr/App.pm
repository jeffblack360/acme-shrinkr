package AcmeShrinkr::App;
use Dancer ':syntax';
use Template;
use DBI;
use Math::Base36 ':all';
# use File::Spec;
# use File::Slurp;
use URI;

our $VERSION = '0.1';

hook before_template_render => sub {
	my $tokens = shift;	
	$tokens->{'base'} = request->base();
	$tokens->{'css_url'} = 'css/style.css';
};
sub connect_db {
	my $dbh = DBI->connect("dbi:SQLite:dbname=".setting('database')) or 
		die $DBI::errstr;
	return $dbh;
}

my $id = 0;
sub init_db {
	my $db = connect_db();
	
	# my $sql = read_file("./db-schema.sql");
	# $db->do($sql) or die $db->errstr;
	
	my $sql = "SELECT MAX(id) FROM link";
	my $sth = $db->prepare($sql) or die $db->errstr;
	$sth->execute() or die $sth->errstr;
	($id) = $sth->fetchrow_array() or die $sth->errstr;
}	

sub get_next_id {
	return ++$id;
}

any ['get', 'post'] => '/' => sub {

	my $msg;
	my $err;
	
	if (request->method() eq "POST") {
		my $uri = URI->new( params->{'url'} );
		
		if ( $uri->scheme !~ /https?/ ) {
			$err = 'Error: Only HTTP or HTTPS URLs are accepted.';
		}
		else {
			my $nid = get_next_id();
			my $code = encode_base36($nid);			
			my $sql = 'INSERT INTO link (id, code, url, count) VALUES (?,?,?,0)';
			my $db = connect_db();
			my $sth = $db->prepare($sql) or die $db->errstr;
			$sth->execute( $nid, $code, $uri->canonical() ) or die $sth->errstr;
			$msg = $uri->as_string . " has been shrunk to " . request->base() . $code;			
		}		
	}

    template 'add.tt', {
		'err' => $err,
		'msg' => $msg,
	};
};

get qr|\A\/(?<code>[A-Za-z0-9]+)\Z| => sub {

	my $decode = decode_base36(uc captures->{'code'} );
	if ( $decode > $id ) {
		send_error(404);
	}
	
	my $db = connect_db();
	my $sql = 'SELECT url, count FROM link WHERE id = ?';
	my $sth = $db->prepare($sql) or die $db->errstr;
	$sth->execute($decode) or die $sth->errstr;
	
	my ($url, $count) = $sth->fetchrow_array() or die $sth->errstr;
	
	$sql = 'UPDATE link SET count = ? WHERE id = ?';
	$sth = $db->prepare($sql) or die $db->errstr;
	$sth->execute(++$count, $decode);
	redirect $url;	
};

get '/:code/stats' => sub {
	my $decode = decode_base36(uc params->{'code'} );
	if ( $decode > $id ) {
		send_error(404);
	}
	
	my $sql = 'SELECT id, code, url, count FROM link WHERE id = ?';
	my $db = connect_db();
	my $sth = $db->prepare($sql) or die $db->errstr;
	$sth->execute($decode) or die $sth->errstr;
	
	my $prev1;
	my $next1;
	unless ( ( $decode - 1 ) < 0 ) {
		$prev1 = encode_base36( $decode - 1 );
	}
	unless ( ( $decode + 1 ) > $id ) {
		$next1 = encode_base36( $decode + 1 );
	}
	
	template 'stats.tt', {
		'stats' => $sth->fetchall_hashref('id'),
		'next1' => $next1,
		'prev1' => $prev1,
	};
};

get '/all_stats' => sub {

	my $sql = 'SELECT id, code, url, count FROM link';
	my $db = connect_db();
	my $sth = $db->prepare($sql) or die $db->errstr;
	$sth->execute() or die $sth->errstr;
	
	template 'stats.tt', {
		'stats' => $sth->fetchall_hashref('id'),
	};
};

init_db();

true;
