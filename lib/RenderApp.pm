package RenderApp;
use Mojo::Base 'Mojolicious';
use Mojo::Base 'Mojolicious::Controller', -async_await;
use Mojo::JSON qw(decode_json);

BEGIN {
    use Mojo::File;
    $main::dirname = Mojo::File::curfile->dirname;

    #RENDER_ROOT is required for initializing conf files
    $ENV{RENDER_ROOT} = $main::dirname->dirname
      unless ( defined( $ENV{RENDER_ROOT} ) );

    #WEBWORK_ROOT is required for PG/lib/WeBWorK/IO
    $ENV{WEBWORK_ROOT} = $main::dirname . '/WeBWorK'
      unless ( defined( $ENV{WEBWORK_ROOT} ) );

    #used for reconstructing library paths from sym-links
    $ENV{OPL_DIRECTORY}                    = "webwork-open-problem-library";
    $WeBWorK::Constants::WEBWORK_DIRECTORY = $main::dirname . "/WeBWorK";
    $WeBWorK::Constants::PG_DIRECTORY      = $main::dirname . "/PG";
    unless ( -r $WeBWorK::Constants::WEBWORK_DIRECTORY ) {
        die "Cannot read webwork root directory at $WeBWorK::Constants::WEBWORK_DIRECTORY";
    }
    unless ( -r $WeBWorK::Constants::PG_DIRECTORY ) {
        die "Cannot read webwork pg directory at $WeBWorK::Constants::PG_DIRECTORY";
    }

	$ENV{MOJO_CONFIG} = (-r "$ENV{RENDER_ROOT}/render_app.conf") ? "$ENV{RENDER_ROOT}/render_app.conf" : "$ENV{RENDER_ROOT}/render_app.conf.dist";
	# $ENV{MOJO_MODE} = 'production';
	# $ENV{MOJO_LOG_LEVEL} = 'debug';
}

use lib "$main::dirname";
print "home directory " . $main::dirname . "\n";

use RenderApp::Model::Problem;
use RenderApp::Controller::RenderProblem;
use RenderApp::Controller::IO;

sub startup {
	my $self = shift;

	# Merge environment variables with config file
	$self->plugin('Config');
	$self->plugin('TagHelpers');
	$self->secrets($self->config('secrets'));
	for ( qw(problemJWTsecret webworkJWTsecret baseURL formURL SITE_HOST STRICT_JWT) ) {
		$ENV{$_} //= $self->config($_);
	};

	$ENV{baseURL} = '' if ( $ENV{baseURL} eq '/' );
	$ENV{SITE_HOST} =~ s|/$||;  # remove trailing slash

	# $r needs to be defined before the SITE_HOST is added to the baseURL
	my $r = $self->routes->under($ENV{baseURL});

	# while iFrame embedded problems are likely to need the baseURL to include SITE_HOST
	# convert to absolute URLs
	$ENV{baseURL} = $ENV{SITE_HOST} . $ENV{baseURL} unless ( $ENV{baseURL} =~ m|^https?://| );
	$ENV{formURL} = $ENV{baseURL} . $ENV{formURL} unless ( $ENV{formURL} =~ m|^https?://| );

	# Handle optional CORS settings
	if (my $CORS_ORIGIN = $self->config('CORS_ORIGIN')) {
		die "CORS_ORIGIN ($CORS_ORIGIN) must be an absolute URL or '*'" 
			unless ($CORS_ORIGIN eq '*' || $CORS_ORIGIN =~ /^https?:\/\//);

		$self->hook(before_dispatch => sub {
			my $c = shift;
            $c->res->headers->header( 'Access-Control-Allow-Origin' => $CORS_ORIGIN );
		});
	}

	# Add Cache-Control and Expires headers to static content from webwork2_files
	if (my $STATIC_EXPIRES = $self->config('STATIC_EXPIRES')) {
	    $STATIC_EXPIRES = int( $STATIC_EXPIRES );
	    my $cache_control_setting = "max-age=$STATIC_EXPIRES";
	    my $no_cache_setting = 'max-age=1, no-cache';
	    $self->hook(after_dispatch => sub {
		my $c = shift;

		# Only process if file requested is under webwork2_files
		return unless ($c->req->url->path =~ '^/webwork2_files/');

		if ($c->req->url->path =~ '/tmp/renderer') {
		    # Treat problem generated files as already expired.
		    # They should not be cached.
		    $c->res->headers->cache_control( $no_cache_setting );
		    $c->res->headers->header(Expires =>
		        Mojo::Date->new(time - 86400) # expired 24 hours ago
		    );
		} else {
		    # Standard "static" files.
		    # They can be cached
		    $c->res->headers->cache_control( $cache_control_setting );
		    $c->res->headers->header(Expires =>
		        Mojo::Date->new(time + $STATIC_EXPIRES)
			);
		}
	    });
	}

	# Models
	$self->helper(newProblem => sub { shift; RenderApp::Model::Problem->new(@_) });

	# Helpers
	$self->helper(validateRequest => sub { RenderApp::Controller::IO::validate(@_) });
	$self->helper(parseRequest => sub { RenderApp::Controller::Render::parseRequest(@_) });
	$self->helper(croak => sub { RenderApp::Controller::Render::croak(@_) });
	$self->helper(logID => sub { shift->req->request_id });
	$self->helper(exception => sub { RenderApp::Controller::Render::exception(@_) });

	# Routes to controller

	$r->any('/render-api')->to('render#problem');
	$r->any('/health' => sub {shift->rendered(200)});
	if ($self->mode eq 'development') {
		$r->any('/')->to('pages#twocolumn');
		$r->any('/opl')->to('pages#oplUI');
		$r->any('/die' => sub {die "what did you expect, flowers?"});
		$r->any('/timeout' => sub {
			my $c = shift;
			my $tx = $c->render_later->tx;
			Mojo::IOLoop->timer(2 => sub {
				$tx = $tx; # prevent $tx from going out of scope
				$c->rendered(200);
			});
		});

		$r->any('/render-api/jwt')->to('render#jwtFromRequest');
		$r->any('/render-api/jwe')->to('render#jweFromRequest');
		$r->any('/render-api/tap')->to('IO#raw');
		$r->post('/render-api/can')->to('IO#writer');
		$r->any('/render-api/cat')->to('IO#catalog');
		$r->any('/render-api/find')->to('IO#search');
		$r->post('/render-api/upload')->to('IO#upload');
		$r->post('/render-api/sma')->to('IO#findNewVersion');
		$r->post('/render-api/unique')->to('IO#findUniqueSeeds');
		$r->post('/render-api/tags')->to('IO#setTags');
	}

    $r->get('/flashcard/*problem' => async sub {
        my $c = shift;

        my %inputs = (
          permissionLevel => 20,
          includeTags => 1,
          showComments => 1,
          sourceFilePath => $c->stash("problem"),
          problemSeed => int(rand(1024)), # TODO Initialize with a random seed
          format => "json",
          outputFormat => "static",
          answersSubmitted => 1,
          showCorrectAnswers => "Show correct answers",
        );

        my $problem = $c->newProblem({ log => $c->log, read_path => $inputs{sourceFilePath}, random_seed => $inputs{problemSeed} });
        return $c->exception($problem->{_message}, status => $problem->{status}) unless $problem->success();

        $c->render_later;
        my $ww_return_json = await $problem->render(\%inputs);

        unless ($problem->success()) {
          $c->log->warn($problem->{_message});
          return $c->render(
            json   => $problem->errport(),
            status => $problem->{status}
          );
        }

        my $ww_return_hash = decode_json($ww_return_json);
        #my @output_errs = checkOutputs($ww_return_hash);
        #if (@output_errs) {
        #  my $err_log = "Output from rendering ".$inputs{sourceFilePath}." contained errors: {";
        #  $err_log .= join "}, {", @output_errs;
        #  $c->log->error($err_log."}");
        #}
        #
        #$ww_return_hash->{debug}->{render_warn} = [@output_errs];

        my $str = $ww_return_hash->{renderedHTML};

        $str =~ s/<head>/<head>\n<script defer src="\/webwork2_files\/js\/answerspoilers.js"><\/script>/;
        $str =~ s/<h3>Results for this submission<\/h3>/<h3>Press any key to reveal the answers<\/h3>/;
        $str =~ s/class="attemptResults"/class="attemptResults" style="display:none;"/;
        $str =~ s/class="attemptResultsSummary"/class="attemptResultsSummary" style="display:none;"/;
        $str =~ s/<p>You can earn partial credit on this problem.<\/p>/<p style="display:none;">You can earn partial credit on this problem.<\/p>/;

        $ww_return_hash->{renderedHTML} = $str;

        $c->respond_to(
          html => { text => $ww_return_hash->{renderedHTML} },
        );
    });

	# pass all requests via ww2_files through to lib/WeBWorK/htdocs
	my $staticPath = $WeBWorK::Constants::WEBWORK_DIRECTORY."/htdocs/";
	$r->any('/webwork2_files/*static' => sub {
		my $c = shift;
		$c->reply->file($staticPath.$c->stash('static'));
	});

	# any other requests fall through
	$r->any('/*fail' => sub {
		my $c = shift;
		my $report = $c->stash('fail')."\nCOOKIE:";
		for my $cookie (@{$c->req->cookies}) {
			$report .= "\n".$cookie->to_string;
		}
		$report .= "\nFORM DATA:";
		foreach my $k (@{$c->req->params->names}) {
			$report .= "\n$k = ".join ', ', @{$c->req->params->every_param($k)};
		}
		$c->log->fatal($report);
		$c->rendered(404)});
}

1;
