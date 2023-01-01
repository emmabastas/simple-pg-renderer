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

use Problem;

sub startup {
    my $self = shift;

    # $r needs to be defined before the SITE_HOST is added to the baseURL
    my $r = $self->routes->under($ENV{baseURL});

    $r->get('/flashcard/*problem' => async sub {
        my $c = shift;

        my $problem_path = $c->stash("problem");
        open my $fh, '<', $problem_path or die "error opening $problem_path: $!";
        my $problem_contents = do { local $/; <$fh> };

        my %inputs = (
          permissionLevel => 20,
          includeTags => 1,
          showComments => 1,
          problemSeed => time(),
          format => "json",
          outputFormat => "static",
          answersSubmitted => 1,
          showCorrectAnswers => "Show correct answers",
        );

        my $problem = Problem->new({
            log => $c->log,
            problem_contents => $problem_contents,
            read_path => $problem_path,
            random_seed => $inputs{problemSeed},
        });

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
