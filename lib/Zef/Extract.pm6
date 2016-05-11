use Zef;

class Zef::Extract does Pluggable {
    method extract($path, $extract-to, Supplier :$logger) {
        $logger.emit({
            level   => DEBUG,
            stage   => EXTRACT,
            phase   => START,
            payload => self,
            message => "Extract Path: {$path}"
        }) if ?$logger;

        die "Can't extract non-existent path: {$path}" unless $path.IO.e;
        die "Can't extract to non-existent path: {$extract-to}" unless $extract-to.IO.e || $extract-to.IO.mkdir;

        my $extractor = self.plugins.first(*.extract-matcher($path));
        die "No extracting backend available" unless ?$extractor;

        if ?$logger {
            $logger.emit({ level => DEBUG, stage => EXTRACT, phase => START, payload => self, message => "Extracting with plugin: {$extractor.^name}" });
            $extractor.stdout.Supply.act: -> $out { $logger.emit({ level => VERBOSE, stage => EXTRACT, phase => LIVE, message => $out }) }
            $extractor.stderr.Supply.act: -> $err { $logger.emit({ level => ERROR,   stage => EXTRACT, phase => LIVE, message => $err }) }
        }

        my $got = $extractor.extract($path, $extract-to);

        $extractor.stdout.done;
        $extractor.stderr.done;

        die "something went wrong extracting {$path} to {$extract-to} with {$.plugins.join(',')}" unless $got;
        return $got;
    }
}
