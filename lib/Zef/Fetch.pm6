use Zef;
use Zef::Utils::URI;

class Zef::Fetch does Pluggable {
    method ACCEPTS($uri) { $ = $uri ~~ @$.plugins }

    method fetch($uri is copy, $save-as, Supplier :$logger) {
        $logger.emit({
            level   => DEBUG,
            stage   => FETCH,
            phase   => START,
            payload => self,
            message => "Fetch URI: {$uri}"
        }) if ?$logger;

        my $fetcher = self.plugins.first(*.fetch-matcher($uri));

        # This belongs somewhere else, but i'm not sure where
        # Mainly for Windows's Rakudo Star for those who do not have `git` installed
        # Mangle the `source-url` (aka $uri) of github urls to their .zip
        return do {
            my $git-zip     = $uri.subst(/^.*?':'/, 'https:').subst(/'.git'$/, '/archive/master.zip');
            my $save-as-zip = $save-as.subst(/'.git'$/, '.zip');
            self.fetch($git-zip, $save-as-zip, :$logger);
        } if !$fetcher && $uri.ends-with('.git') && $uri.starts-with('http:' | 'ssh:' | 'git');

        die "No fetching backend available" unless ?$fetcher;

        if ?$logger {
            $logger.emit({ level => DEBUG, stage => FETCH, phase => START, payload => self, message => "Fetching with plugin: {$fetcher.^name}" });
            $fetcher.stdout.Supply.act: -> $out { $logger.emit({ level => VERBOSE, stage => FETCH, phase => LIVE, message => $out }) }
            $fetcher.stderr.Supply.act: -> $err { $logger.emit({ level => ERROR,   stage => FETCH, phase => LIVE, message => $err }) }
        }

        my $got = $fetcher.fetch($uri, $save-as);

        $fetcher.stdout.done;
        $fetcher.stderr.done;

        return $got;
    }
}
