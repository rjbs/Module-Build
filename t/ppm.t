#!/usr/bin/perl -w

use strict;
use File::Spec ();

BEGIN {
  my $common_pl = File::Spec->catfile( 't', 'common.pl' );
  require $common_pl;
}

use Test::More;
use Module::Build;

my( $manpage_support, $HTML_support );

{ local $SIG{__WARN__} = sub {};

  my $mb = Module::Build->current;
  $mb->verbose( 0 );

  $manpage_support = $mb->feature('manpage_support');
  $HTML_support    = $mb->feature('HTML_support');

  my $have_c_compiler;
  stderr_of( sub {$have_c_compiler = $mb->have_c_compiler} );

  if ( ! $mb->feature('C_support') ) {
    plan skip_all => 'C_support not enabled';
  } elsif ( ! $have_c_compiler ) {
    plan skip_all => 'C_support enabled, but no compiler found';
  } elsif ( ! eval {require Archive::Tar} ) {
    plan skip_all => "Archive::Tar not installed to read archives.";
  } elsif ( ! eval {IO::Zlib->VERSION(1.01)} ) {
    plan skip_all => "IO::Zlib 1.01 required to read compressed archives.";
  } else {
    plan tests => 12;
  }
}


use Cwd ();
my $cwd = Cwd::cwd;
my $tmp = File::Spec->catdir( $cwd, 't', '_tmp' );


use DistGen;
my $dist = DistGen->new( dir => $tmp, xs => 1 );
$dist->add_file( 'hello', <<'---' );
#!perl -w
print "Hello, World!\n";
__END__

=pod

=head1 NAME

hello

=head1 DESCRIPTION

Says "Hello"

=cut
---
$dist->change_file( 'Build.PL', <<"---" );

my \$build = new Module::Build(
  module_name => @{[$dist->name]},
  license     => 'perl',
  scripts     => [ 'hello' ],
);

\$build->create_build_script;
---
$dist->regen;

chdir( $dist->dirname ) or die "Can't chdir to '@{[$dist->dirname]}': $!";

use File::Spec::Functions qw(catdir);

use Module::Build;
my @installstyle = qw(lib perl5);
my $mb = Module::Build->new_from_context(
  verbose => 0,
  quiet   => 1,

  installdirs => 'site',
  config => {
    manpage_reset(), html_reset(),
    ( $manpage_support ?
      ( installsiteman1dir  => catdir($tmp, 'site', 'man', 'man1'),
        installsiteman3dir  => catdir($tmp, 'site', 'man', 'man3') ) : () ),
    ( $HTML_support ?
      ( installsitehtml1dir => catdir($tmp, 'site', 'html'),
        installsitehtml3dir => catdir($tmp, 'site', 'html') ) : () ),
  },
);



$mb->dispatch('ppd', args => {codebase => '/path/to/codebase-xs'});

(my $dist_filename = $dist->name) =~ s/::/-/g;
my $ppd = slurp($dist_filename . '.ppd');

my $perl_version = Module::Build::PPMMaker->_ppd_version($mb->perl_version);
my $varchname = Module::Build::PPMMaker->_varchname($mb->config);

# This test is quite a hack since with XML you don't really want to
# do a strict string comparison, but absent an XML parser it's the
# best we can do.
is $ppd, <<"---";
<SOFTPKG NAME="$dist_filename" VERSION="0,01,0,0">
    <TITLE>@{[$dist->name]}</TITLE>
    <ABSTRACT>Perl extension for blah blah blah</ABSTRACT>
    <AUTHOR>A. U. Thor, a.u.thor\@a.galaxy.far.far.away</AUTHOR>
    <IMPLEMENTATION>
        <PERLCORE VERSION="$perl_version" />
        <OS NAME="$^O" />
        <ARCHITECTURE NAME="$varchname" />
        <CODEBASE HREF="/path/to/codebase-xs" />
    </IMPLEMENTATION>
</SOFTPKG>
---



$mb->dispatch('ppmdist');
is $@, '';

my $tar = Archive::Tar->new;

my $tarfile = $mb->ppm_name . '.tar.gz';
$tar->read( $tarfile, 1 );

my $files = { map { $_ => 1 } $tar->list_files };

exists_ok($files, 'blib/arch/auto/Simple/Simple.' . $mb->config('dlext'));
exists_ok($files, 'blib/lib/Simple.pm');
exists_ok($files, 'blib/script/hello');

SKIP: {
  skip( "manpage_support not enabled.", 2 ) unless $manpage_support;

  exists_ok($files, 'blib/man3/Simple.' . $mb->config('man3ext'));
  exists_ok($files, 'blib/man1/hello.' . $mb->config('man1ext'));
}

SKIP: {
  skip( "HTML_support not enabled.", 2 ) unless $HTML_support;

  exists_ok($files, 'blib/html/site/lib/Simple.html');
  exists_ok($files, 'blib/html/bin/hello.html');
}

$tar->clear;
undef( $tar );

$mb->dispatch('realclean');
$dist->clean;


SKIP: {
  skip( "HTML_support not enabled.", 3 ) unless $HTML_support;

  # Make sure html documents are generated for the ppm distro even when
  # they would not be built during a normal build.
  $mb = Module::Build->new_from_context(
    verbose => 0,
    quiet   => 1,

    installdirs => 'site',
    config => {
      html_reset(),
      installsiteman1dir  => catdir($tmp, 'site', 'man', 'man1'),
      installsiteman3dir  => catdir($tmp, 'site', 'man', 'man3'),
    },
  );

  $mb->dispatch('ppmdist');
  is $@, '';

  $tar = Archive::Tar->new;
  $tar->read( $tarfile, 1 );

  $files = {map { $_ => 1 } $tar->list_files};

  exists_ok($files, 'blib/html/site/lib/Simple.html');
  exists_ok($files, 'blib/html/bin/hello.html');

  $tar->clear;

  $mb->dispatch('realclean');
  $dist->clean;
}


chdir( $cwd ) or die "Can''t chdir to '$cwd': $!";
$dist->remove;

use File::Path;
rmtree( $tmp );


########################################

sub exists_ok {
  my $files = shift;
  my $file  = shift;
  local $Test::Builder::Level = $Test::Builder::Level + 1;
  ok exists( $files->{$file} ) && $files->{$file}, $file;
}

