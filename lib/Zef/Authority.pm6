use IO::Socket::SSL;

class Zef::Authority {
    has $.session-key is rw;
    has $!sock;

    submethod BUILD( IO::Socket::SSL :$ssl-sock ) {
        $!sock = $ssl-sock // IO::Socket::SSL.new(:host<zef.pm>, :port(443));
    } 

    method login(:$username, :$password) {
        my $data = to-json({ username => $username, password => $password }) // fail "Bad JSON";
        $!sock.send("POST /api/login HTTP/1.0\r\nHost: zef.pm\r\nContent-Length: {$data.chars}\r\n\r\n{$data}");
        my $recv = $!sock.recv.split("\r\n\r\n").[1];
        my %result = try %(from-json($recv));

        if %result<success> {
            $.session-key = %result<newkey> // fail "Session-key problem";
            return True;
        } 
        elsif %result<failure> {
            $*ERR = %result<reason>;
            return False;
            #fail "Login failed with error: {%result<reason>}";
        } 

        fail "Problem receiving data";
    }

    method register(:$username, :$password) {
        my $data = to-json({ username => $username, password => $password });
        $!sock.send("POST /api/register HTTP/1.0\r\nHost: zef.pm\r\nContent-Length: {$data.chars}\r\n\r\n{$data}");
        my $recv = $!sock.recv.split("\r\n\r\n").[1];
        my %result = try %(from-json($recv));
        
        if %result<success> {
            $.session-key = %result<newkey> // fail "Session-key problem";            
            return True;
        } 
        elsif %result<failure> {
            $*ERR = %result<reason>;
            return False;
            #fail "Registration failed with error: {%result<reason>}";
        } 

        fail "Problem receiving data";
    }

    method search(*@terms) {
        my %results;
        for @terms -> $term {
            my $data = to-json({ query => $term });
            $!sock.send("POST /api/search HTTP/1.0\r\nHost: zef.pm\r\nContent-Length: {$data.chars}\r\n\r\n{$data}");
            my $recv = $!sock.recv.split("\r\n\r\n").[1] or fail "No data received";
            my @term-results = try @(from-json($recv));
            %results{$term} = @term-results;
        }

        return [] ~~ all(%results.values) ?? Hash !! %results;
    }

    method push(*@targets, :$session-key, :@exclude?, :$force?) {
        use MIME::Base64;
        for @targets -> $target {
            my $data = '';
            my @paths = $target.IO.dir;
            my @files;
            my @failures;

            while @paths.shift -> $path {
                next if $path ~~ any @exclude;
                given $path.IO {
                    when :d { for .dir -> $io { @paths.push: $io } }
                    when :f { @files.push($_) }
                }            
            }

            for @files -> $path {
                my $buff = try { 
                        CATCH { default { } }
                        MIME::Base64.encode-str($path.IO.slurp, one-line => True);
                    } // try {
                        my $b = Buf.new;
                        my $f = open $path, :r;
                        while !$f.eof { 
                            $b ~= $f.read(1024); 
                        }
                        $f.close;
                        CATCH { default { } }
                        MIME::Base64.encode($b, one-line => True);
                    } // fail "Failed to encode data: { $path }";

                if $buff !~~ Str {
                    @failures.push($path);
                    last unless $force;
                } 
                
                $data ~= "{nqp::stat($path.Str, nqp::const::STAT_PLATFORM_MODE).base(8)}:{$path.Str.subst(/ ^ $target /, '')}\r\n{$buff}\r\n";
            }

            if !$force && @failures {
                $*ERR.print("Failed to package the following files:\n\t");
                warn @failures.join("\n\t");
            } 

            my $metf = try {'META.info'.IO.slurp} \ 
                // try {'META6.json'.IO.slurp}    \ 
                // fail "Couldn't find META6.json or META.info";

            my $json = to-json({ key => $session-key, data => $data, meta => %(from-json($metf)) });
            $json.chars.say;
            $!sock.send("POST /api/push HTTP/1.0\r\nHost: zef.pm\r\nContent-Length: {$json.chars}\r\n\r\n{$json}");
            my $recv   = $!sock.recv;
            my %result = try %(from-json($recv.split("\r\n\r\n")[1]));
            
            if %result<error> {
                $*ERR = "Error pushing module to server: {%result<error>}";
                return False;
            } 
            else {
                $*ERR = "Unknown error - Reply from server:\n{%result.perl}";
                return False;
            }

            return True;
        }        
    }
}