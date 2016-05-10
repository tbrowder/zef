use Zef;
use Zef::Utils::FileSystem;
use Zef::Distribution;
use Zef::Distribution::DependencySpecification;

# So now that this needs both the extractor *and* fetcher
# it may be time to rethink how some of this is designed
class Zef::ContentStorage::P6C does ContentStorage {
    has $.mirrors;
    has $.auto-update;
    has $.fetcher   is rw;
    has $.extractor is rw;
    has $.cache     is rw;
    has $.temp      is rw;

    has @!dists;

    method !gather-dists {
        once { self.update } if $.auto-update || !self!package-list-file.e;
        @!dists = cache gather for self!slurp-package-list -> $meta {
            my $dist = Zef::Distribution.new(|%($meta));
            take $dist;
        }
    }

    method available {
        my $candidates := gather for self!gather-dists -> $dist {
            take Candidate.new(
                dist => $dist,
                uri  => ($dist.source-url || $dist.hash<support><source>),
                from => $?CLASS.^name,
                as   => $dist.identity,
            );
        }
    }

    method IO {
        my $dir = $!cache.IO.child('p6c').IO;
        $dir.mkdir unless $dir.e;
        $dir;
    }

    method !package-list-file  {
        my $dir = $!cache.IO.child('p6c');
        die "failed to create directory {$dir}"
            unless ($dir.IO.e || mkdir($dir));
        $ = $dir.child('p6c.json');
    }
    method !slurp-package-list { @ = |from-json(self!package-list-file.slurp) }

    method update {
        die "Failed to update p6c" unless $!mirrors.first: -> $uri {
            my $stage-at = $!temp.IO.child($uri.IO.basename);
            die "failed to create directory: {$!temp.absolute}"
                unless ($!temp.IO.e || mkdir($!temp));

            my $save-to    = $!fetcher.fetch($uri, $stage-at);
            my $stored-at  = $!extractor.extract($save-to, $save-to ~ '.extracted');
            my $projects   = list-paths( $stored-at, :f, :!d, :r ).first(* ~~ /'.json'$/);

            try copy($projects, self!package-list-file);
        }
        @!dists = |self!slurp-package-list.map: { $ = Zef::Distribution.new(|%($_)) }
    }

    # todo: handle %fields
    # todo: search for up to $max-results number of candidates for each *dist* (currently only 1 candidate per identity)
    method search(:$max-results = 5, *@identities, *%fields) {
        return () unless @identities || %fields;
        my @wanted = @identities;
        my %specs  = @wanted.map: { $_ => Zef::Distribution::DependencySpecification.new($_) }

        gather DIST: for self!gather-dists -> $dist {
            for @identities.grep(* ~~ any(@wanted)) -> $wants {
                last DIST unless +@wanted;
                if ?$dist.contains-spec( %specs{$wants} ) {
                    my $candidate = Candidate.new(
                        dist => $dist,
                        uri  => ($dist.source-url || $dist.hash<support><source>),
                        as   => $wants,
                        from => $?CLASS.^name,
                    );
                    @wanted.splice(@wanted.first(/$wants/, :k), 1);
                    take $candidate;
                }
            }
        }
    }
}