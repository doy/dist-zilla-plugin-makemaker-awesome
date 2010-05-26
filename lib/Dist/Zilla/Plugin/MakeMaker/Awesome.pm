package Dist::Zilla::Plugin::MakeMaker::Awesome;

use Moose;
use MooseX::Types::Moose qw< Str ArrayRef HashRef >;
use Moose::Autobox;
use List::MoreUtils qw(any uniq);
use Dist::Zilla::File::InMemory;
use namespace::autoclean;

extends 'Dist::Zilla::Plugin::MakeMaker';

with 'Dist::Zilla::Role::BuildRunner';
with 'Dist::Zilla::Role::PrereqSource';
with 'Dist::Zilla::Role::InstallTool';
with 'Dist::Zilla::Role::TestRunner';
with 'Dist::Zilla::Role::TextTemplate';

has MakeFile_PL_template => (
    is            => 'ro',
    isa           => 'Str',
    lazy_build    => 1,
    documentation => "The Text::Template used to construct the ExtUtils::MakeMaker Makefile.PL",
);

sub _build_MakeFile_PL_template {
    my ($self) = @_;
    my $template = <<'TEMPLATE';
# This Makefile.PL for {{ $distname }} was generated by Dist::Zilla.
# Don't edit it but the dist.ini used to construct it.
{{ $perl_prereq ? qq<BEGIN { require $perl_prereq; }> : ''; }}
use strict;
use warnings;
use ExtUtils::MakeMaker {{ $eumm_version }};
{{ $share_dir_block[0] }}
my {{ $WriteMakefileArgs }}

unless ( eval { ExtUtils::MakeMaker->VERSION(6.56) } ) {
  my $br = delete $WriteMakefileArgs{BUILD_REQUIRES};
  my $pp = $WriteMakefileArgs{PREREQ_PM}; 
  for my $mod ( keys %$br ) {
    if ( exists $pp->{$mod} ) {
      $pp->{$mod} = $br->{$mod} if $br->{$mod} > $pp->{$mod}; 
    }
    else {
      $pp->{$mod} = $br->{$mod};
    }
  }
}

delete $WriteMakefileArgs{CONFIGURE_REQUIRES}
  unless eval { ExtUtils::MakeMaker->VERSION(6.52) };

WriteMakefile(%WriteMakefileArgs);
{{ $share_dir_block[1] }}
TEMPLATE

  return $template;
}

has WriteMakefile_args => (
    is            => 'ro',
    isa           => HashRef,
    auto_deref    => 1,
    lazy_build    => 1,
    documentation => "The arguments passed to ExtUtil::MakeMaker's WriteMakefile()",
);

sub _build_WriteMakefile_args {
    my ($self) = @_;

    (my $name = $self->zilla->name) =~ s/-/::/g;
    my $test_dirs = $self->test_dirs;

    my $prereqs = $self->zilla->prereqs;
    my $perl_prereq = $prereqs->requirements_for(qw(runtime requires))
    ->as_string_hash->{perl};

    my $prereqs_dump = sub {
        $prereqs->requirements_for(@_)
        ->clone
        ->clear_requirement('perl')
        ->as_string_hash;
    };

    my $build_prereq
        = $prereqs->requirements_for(qw(build requires))
        ->clone
        ->add_requirements($prereqs->requirements_for(qw(test requires)))
        ->as_string_hash;

    my %WriteMakefile = (
        DISTNAME  => $self->zilla->name,
        NAME      => $name,
        AUTHOR    => $self->zilla->authors->join(q{, }),
        ABSTRACT  => $self->zilla->abstract,
        VERSION   => $self->zilla->version,
        LICENSE   => $self->zilla->license->meta_yml_name,
        EXE_FILES => [ $self->exe_files ],

        CONFIGURE_REQUIRES => $prereqs_dump->(qw(configure requires)),
        BUILD_REQUIRES     => $build_prereq,
        PREREQ_PM          => $prereqs_dump->(qw(runtime   requires)),

        test => { TESTS => join q{ }, sort keys %$test_dirs },
    );

    return \%WriteMakefile;
}


has WriteMakefile_dump => (
    is            => 'ro',
    isa           => Str,
    lazy_build    => 1,
    documentation => "A Data::Dumper Str for using WriteMakefile_args used by MakeFile_PL_template"
);

sub _build_WriteMakefile_dump {
    my ($self) = @_;
    # Get arguments for WriteMakefile
    my %write_makefile_args = $self->WriteMakefile_args;

    my $makefile_args_dumper = do {
        local $Data::Dumper::Quotekeys = 1;
        local $Data::Dumper::Indent    = 1;
        local $Data::Dumper::Sortkeys  = 1;
        Data::Dumper->new(
            [ \%write_makefile_args ],
            [ '*WriteMakefileArgs' ],
        );
    };

    return $makefile_args_dumper->Dump;
}

has test_dirs => (
    is            => 'ro',
    isa           => HashRef[Str],
    auto_deref    => 1,
    lazy_build    => 1,
    documentation => "The test directories given to ExtUtil::MakeMaker's test (in munged form)",
);

sub _build_test_dirs {
    my ($self) = @_;

    my %test_dirs;
    for my $file ($self->zilla->files->flatten) {
        next unless $file->name =~ m{\At/.+\.t\z};
        (my $dir = $file->name) =~ s{/[^/]+\.t\z}{/*.t}g;

        $test_dirs{ $dir } = 1;
    }

    return \%test_dirs;
}

has bin_dirs => (
    is            => 'ro',
    isa           => ArrayRef[Str],
    auto_deref    => 1,
    lazy_build    => 1,
    documentation => "The bin/ or script/ directories used by ->exe_files",
);

sub _build_bin_dirs {
    my ($self) = @_;
    
    my @bin_dirs = uniq map {; $_->bin->flatten   } $self->dir_plugins;

    return \@bin_dirs;
}

has share_dirs => (
    is            => 'ro',
    isa           => ArrayRef[Str],
    auto_deref    => 1,
    lazy_build    => 1,
    documentation => "The share directories used by File::ShareDir",
);

sub _build_share_dirs {
    my ($self) = @_;

    my @share_dirs  = uniq map {; $_->share->flatten } $self->dir_plugins;    

    return \@share_dirs;
}

has dir_plugins => (
    is            => 'ro',
    isa           => ArrayRef[Str],
    auto_deref    => 1,
    lazy_build    => 1,
    documentation => "The plugin directories, used by ShareDir",
);

sub _build_dir_plugins {
    my ($self) = @_;

    my @dir_plugins = $self->zilla->plugins
        ->grep( sub { $_->isa('Dist::Zilla::Plugin::InstallDirs') })
        ->flatten;

    return \@dir_plugins;
}

has exe_files => (
    is            => 'ro',
    isa           => ArrayRef[Str],
    auto_deref    => 1,
    lazy_build    => 1,
    documentation => "The test directories given to ExtUtil::MakeMaker's EXE_FILES (in munged form)",
);

sub _build_exe_files {
    my ($self) = @_;
    
    my @exe_files = $self->zilla->files
        ->grep(sub { my $f = $_; any { $f->name =~ qr{^\Q$_\E[\\/]} } $self->bin_dirs; })
        ->map( sub { $_->name })
        ->flatten;

    return \@exe_files;
}

has share_dir_block => (
    is            => 'ro',
    isa           => ArrayRef[Str],
    auto_deref    => 1,
    lazy_build    => 1,
    documentation => "The share dir block used in `MakeFile_PL_template'",
);

sub _build_share_dir_block {
    my ($self) = @_;

    my @share_dirs = $self->share_dirs;

    my @share_dir_block = (q{}, q{});

    if ($share_dirs[0]) {
        my $share_dir = quotemeta $share_dirs[0];
        @share_dir_block = (
            qq{use File::ShareDir::Install;\ninstall_share "$share_dir";\n},
            qq{package\nMY;\nuse File::ShareDir::Install qw(postamble);\n},
        );
    }

    return \@share_dir_block;
}

sub register_prereqs {
    my ($self) = @_;

    $self->zilla->register_prereqs(
        { phase => 'configure' },
        'ExtUtils::MakeMaker' => $self->eumm_version,
    );

    return {} unless uniq map {; $_->share->flatten } $self->dir_plugins;

    $self->zilla->register_prereqs(
        { phase => 'configure' },
        'File::ShareDir::Install' => 0.03,
    );

    return {};
}

sub setup_installer {
    my ($self, $arg) = @_;

    ## Sanity checks
    confess "can't install files with whitespace in their names"
        if grep { /\s/ } $self->exe_files;

    my @share_dirs = $self->share_dirs;

    confess "can't install more than one ShareDir" if @share_dirs > 1;

    my @share_dir_block = $self->share_dir_block;

    my $makefile_dump = $self->WriteMakefile_dump;
    my $perl_prereq = $self->zilla->prereqs->requirements_for(qw(runtime requires))
        ->as_string_hash->{perl};
    my $content = $self->fill_in_string(
        $self->MakeFile_PL_template,
        {
            eumm_version      => \($self->eumm_version),
            perl_prereq       =>  \$perl_prereq,
            share_dir_block   => \@share_dir_block,
            WriteMakefileArgs => \$makefile_dump,
        },
    );

    my $file = Dist::Zilla::File::InMemory->new({
        name    => 'Makefile.PL',
        content => $content,
    });

    $self->add_file($file);
    return;
}

__PACKAGE__->meta->make_immutable;

__END__

=head1 NAME

Dist::Zilla::Plugin::MakeMaker::Awesome - A more awesome MakeMaker plugin for L<Dist::Zilla>

=head1 DESCRIPTION

L<Dist::Zilla>'s L<MakeMaker|Dist::Zilla::Plugin::MakeMaker> plugin is
limited, if you want to stray from the marked path and do something
that would normally be done in a C<package MY> section or otherwise
run custom code in your F<Makefile.PL> you're out of luck.

This plugin is 100% compatable with L<Dist::Zilla::Plugin::MakeMaker>,
but if you need something more complex you can just subclass it:

Then, in your F<dist.ini>:

    ;; Replace [MakeMaker]
    ;[MakeMaker]
    [MakeMaker::Awesome]

More complex use, adding a C<package MY> section to your
F<Makefile.PL>:

In your F<dist.ini>:

    [=inc::MyDistMakeMaker / MyDistMakeMaker]

Then in your F<inc/MyDistMakeMaker.pm>, real example from L<Hailo>
(which has C<[=inc::HailoMakeMaker / HailoMakeMaker]> in its
F<dist.ini>):

    package inc::HailoMakeMaker;
    use Moose;
    
    extends 'Dist::Zilla::Plugin::MakeMaker::Awesome';
    
    override _build_MakeFile_PL_template => sub {
        my ($self) = @_;
        my $template = super();
    
        $template .= <<'TEMPLATE';
    package MY;
    
    sub test {
        my $inherited = shift->SUPER::test(@_);
    
        # Run tests with Moose and Mouse
        $inherited =~ s/^test_dynamic :: pure_all\n\t(.*?)\n/test_dynamic :: pure_all\n\tANY_MOOSE=Mouse $1\n\tANY_MOOSE=Moose $1\n/m;
    
        return $inherited;
    }
    TEMPLATE
    
        return $template;
    };
    
    __PACKAGE__->meta->make_immutable;

Or maybe you're writing an XS distro and want to pass custom arguments
to C<WriteMakefile()>, here's an example of adding a C<LIBS> argument
in L<re::engine::PCRE>:
    
    package inc::PCREMakeMaker;
    use Moose;
    
    extends 'Dist::Zilla::Plugin::MakeMaker::Awesome';
    
    override _build_WriteMakefile_args => sub { +{
        # Add LIBS => to WriteMakefile() args
        %{ super() },
        LIBS => [ '-lpcre' ],
    } };
    
    __PACKAGE__->meta->make_immutable;

And another example from L<re::engine::Plan9>:

    package inc::Plan9MakeMaker;
    use Moose;
    
    extends 'Dist::Zilla::Plugin::MakeMaker::Awesome';
    
    override _build_WriteMakefile_args => sub {
        my ($self) = @_;
    
        our @DIR = qw(libutf libfmt libregexp);
        our @OBJ = map { s/\.c$/.o/; $_ }
                   grep { ! /test/ }
                   glob "lib*/*.c";
    
        return +{
            %{ super() },
            DIR           => [ @DIR ],
            INC           => join(' ', map { "-I$_" } @DIR),
    
            # This used to be '-shared lib*/*.o' but that doesn't work on Win32
            LDDLFLAGS     => "-shared @OBJ",
        };
    };
    
    __PACKAGE__->meta->make_immutable;

If you have custom code in your L<ExtUtils::MakeMaker>-based
L<Makefile.PL> that L<Dist::Zilla> can't replace via its default
facilities you'll be able replace it by using this module.

Even if your F<Makefile.PL> isn't L<ExtUtils::MakeMaker>-based you
should be able to override it. You'll just have to provide a new
L</"_build_MakeFile_PL_template">.

=head1 OVERRIDE

These are the methods you can currently L<override> in your custom
F<inc/> module. The work that this module does is entirely done in
small modular methods that can be overriden in your subclass. Here are
some of the highlights:

=head2 _build_MakeFile_PL_template

Returns L<Text::Template> string used to construct the F<Makefile.PL>.

=head2 _build_WriteMakefile_args

A C<HashRef> of arguments that'll be passed to
L<ExtUtils::MakeMaker>'s C<WriteMakefile> function.

=head2 _build_WriteMakefile_dump

Takes the return value of L</"_build_WriteMakefile_args"> and
constructs a L<Str> that'll be included in the F<Makefile.PL> by
L</"_build_MakeFile_PL_template">.

=head2 test_dirs

=head2 bin_dirs

=head2 share_dirs

=head2 exe_files

The test/bin/share dirs and exe_files. These'll all be passed to
F</"_build_WriteMakefile_args"> later.

=head2 dir_plugins

Used for L<Dist::Zilla::Plugin::ShareDir> support. Don't touch it if
you don't need some deep ShareDir magic.

=head2 _build_share_dir_block

An C<ArrayRef[Str]> with two elements to be used by
L</"_build_MakeFile_PL_template">. The first will declare your
L<ShareDir|File::ShareDir::Install> and the second will add a magic
C<package MY> section to install it. Deep magic.

=head2 OTHER

The main entry point is C<setup_installer> via the
L<Dist::Zilla::Role::InstallTool> role. There are also other magic
Dist::Zilla roles, check the source for more info.

=head1 BUGS

This plugin would suck less if L<Dist::Zilla> didn't use a INI-based
config system so you could add a stuff like this in your main
configuration file like you can with L<Module::Install>.

The F<.ini> file format can only support key-value pairs whereas any
complex use of L<ExtUtils::MakeMaker> requires running custom Perl
code and passing complex data structures to C<WriteMakefile>.

=head1 AUTHOR

E<AElig>var ArnfjE<ouml>rE<eth> Bjarmason <avar@cpan.org>

=head1 LICENSE AND COPYRIGHT

Copyright 2010 E<AElig>var ArnfjE<ouml>rE<eth> Bjarmason <avar@cpan.org>

This program is free software, you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
