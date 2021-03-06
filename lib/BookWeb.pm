package BookWeb;
use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Feed;
use Dancer::Session;

use Net::Amazon;
use DateTime;

our $VERSION = '0.1';

hook before => sub {
    if (! session('logged_in') and ! public_path(request->path_info)) {
        var requested_path => request->path_info;
        request->path_info('/login');
    }
};

get '/' => sub {
    set_plugins();
    my $books_rs = schema->resultset('Book');
    
    template 'index', {
        reading => [ $books_rs->search({
            started => { '!=' => undef },
            ended => undef,
        }) ],
        read    => [ $books_rs->search({
            ended => { '!=' => undef },
        }) ],
        to_read => [ $books_rs->search({
            started => undef,
        }) ],
        logged  => session 'logged_in',
    };
};

get '/start/:isbn' => sub {
    set_plugins();
    my $books_rs = schema->resultset('Book');
    my $book = $books_rs->find({ isbn => param('isbn')});

    if ($book) {
        $book->update({started => DateTime->now});
    }

    return redirect '/';
};

get '/end/:isbn' => sub {
    set_plugins();
    my $books_rs = schema->resultset('Book');
    my $book = $books_rs->find({ isbn => param('isbn')});

    if ($book) {
        $book->update({ended => DateTime->now});
    }

    return redirect '/';
};

get '/add/:isbn' => sub {
    set_plugins();
    my $author_rs = schema->resultset('Author');

    my $amz = get_amazon();

    # Search for the book at Amazon
    my $resp = $amz->search(asin => param('isbn'));

    unless ($resp->is_success) {
        die 'Error: ', $resp->message;
    }

    my $book = $resp->properties;
    my $title = $book->ProductName;
    my $author_name = ($book->authors)[0];
    my $imgurl = $book->ImageUrlMedium;

    # Find or create the author
    my $author = $author_rs->find_or_create({
        name => $author_name,
    });

    # Add the book to the author
    $author->add_to_books({
        isbn => param('isbn'),
        title => $title,
        image_url => $imgurl,
    });

    return redirect '/';
};

get '/feed' => sub {
    return redirect '/feed/atom';
};

get '/feed/:format' => sub {
    set_plugins();
    my $books_rs = schema->resultset('Book');
    
    my @books = ($books_rs->search({
        started => { '!=' => undef },
    }));
    
    my $feed = create_feed(
        format => params->{format},
        title => 'Reading List',
        link => 'http://books.dave.org.uk/',
        modified => DateTime->now,
        entries => [ map { title => $_->title }, @books ],
    );
    
    return $feed;
};

post '/search' => sub {
    my $amz = get_amazon();
   
    my $resp = $amz->search(
        keyword => param('search'),
        mode => 'books',
    );

    my %data;
    $data{search} = param('search');
    $data{logged} = session 'logged_in';
    if ($resp->is_success) {
        $data{books} = [ $resp->properties ];
    } else {
        $data{error} = $resp->message;
    }

    template 'results', \%data;
};

get '/login' => sub {
    template 'login', { path => vars->{requested_path } };  
};

post '/login' => sub {
    if (params->{user} eq $ENV{BOOK_USER} && params->{pass} eq $ENV{BOOK_PASS}) {
        session 'logged_in' => 1;
    }

    redirect  params->{path} || '/';
};

get '/logout' => sub {
    session 'logged_in' => 0;
    
    redirect '/';
};

sub get_amazon {
     return Net::Amazon->new(
        token => $ENV{AMAZON_KEY},
        secret_key => $ENV{AMAZON_SECRET},
        associate_tag => $ENV{AMAZON_ASSTAG},
        locale => 'uk',
    ) or die "Cannot connect to Amazon\n";
}

sub set_plugins {
    set plugins => {
        DBIC => {
            book => {
                schema_class => 'Book',
                dsn => 'dbi:mysql:database=books',
                user => $ENV{BOOK_DB_USER},
                pass => $ENV{BOOK_DB_PASS},
            }
        }
    };    
}

my @public_paths = qw[/ /login /search];
my %public_path = map { $_ => 1 } @public_paths;

sub public_path {
    my $path = shift;
    
    return 1 if $public_path{$path};
    return 1 if $path =~ m|^/feed|;
    return;
}

true;
