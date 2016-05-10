use Zef;
use Zef::Shell;

class Zef::Shell::PowerShell is Zef::Shell does Probeable {
    has @.invocation = 'powershell', '-NoProfile', '-ExecutionPolicy', 'unrestricted', '-Command';

    method probe {
        state $powershell-probe = !$*DISTRO.is-win ?? False !! try {
            try {
                my $proc = zrun('powershell', '-help', :out, :err);
                my @out  = $proc.out.lines;
                my @err  = $proc.err.lines;
                $proc.out.close;
                $proc.err.close;
                CATCH {
                    when X::Proc::Unsuccessful { return False }
                    default { return False }
                }
                so $proc;
            }
        }
        ?$powershell-probe;
    }
}
