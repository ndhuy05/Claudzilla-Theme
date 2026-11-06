#!/usr/bin/perl -0777
# hud-data.mjs key/value lines -> E2 layout: identity row, rule, meters in two columns (ctx over cch | 5h over wk), rule, activity row.
# hud.compact in claudzilla.json: no rules, and all meters on one row when the width allows.
# Personal copy of claudzilla's claude/hud/hud-filter.pl: opencode palette, block bars, no email, time, date or session info.
use strict; use warnings;
# This copy lives outside the clone, so the version and trace.pl are read from the clone the hud link points into.
use Cwd 'abs_path';
my $CZ_HUD = abs_path(($ENV{CLAUDE_CONFIG_DIR} // "$ENV{HOME}/.claude") . '/hud') // '';
# stdin, stdout, files and `git` output are UTF-8: decode on read, so non-ASCII paths aren't encoded twice.
# Invalid bytes (a branch name git allows) become U+FFFD, quietly: a statusline has no stderr reader.
use open qw(:std :encoding(UTF-8));
no warnings 'utf8';
# C0/C1 control chars in text the filter reads itself (session name, branch) would reach the terminal.
sub clean { my $s = shift; $s =~ tr/\x00-\x1f\x7f-\x9f/ / if defined $s; return $s }

my $raw = do { local $/; <STDIN> };
(my $txt = $raw) =~ s/\e\[[0-9;]*m//g;

# no terminal width in the statusline JSON: trust COLUMNS, else ask the tty, else assume 114
my $W = 114;
{   my $cols = $ENV{COLUMNS};
    unless ($cols && $cols =~ /^\d+$/ && $cols > 20) {
        ($cols) = (`stty size < /dev/tty 2>/dev/null` // '') =~ /^\d+\s+(\d+)/;
    }
    $W = $cols - 4 if $cols && $cols =~ /^\d+$/ && $cols > 20;
}

# install.sh leaves this marker when the user declines MesloLGS NF: fall back to symbols every mono font has
my ($G_ON, $G_OFF, $G_BRANCH, $G_SKILL, $G_CACHE) =
    -e (($ENV{CLAUDE_CONFIG_DIR} // "$ENV{HOME}/.claude") . '/.claudzilla-basic-glyphs')
    ? ("\x{25A0}", "\x{25A1}", "\x{203A}", "\x{25B8}", "\x{25A0}")
    : ("\x{25B0}", "\x{25B1}", "\x{2387}", "\x{2691}", "\x{25AC}");
# block bars: every mono font has them, so no fallback needed
($G_ON, $G_OFF, $G_CACHE) = ("\x{2588}", "\x{2591}", "\x{2588}");

my %f = map { /^([^\t]+)\t(.*)$/ ? ($1, $2) : () } split /\n/, $txt;
my ($id, $META_CWD, $EFFORT, $SID) = @f{qw(id cwd effort sid)};
# session name (/rename, or derived like "maxis-24") - the handle peers message us by.
# Not in the statusline JSON, so look it up in the per-pid session registry.
my $sname;
if ($SID) {
    my $dir = ($ENV{CLAUDE_CONFIG_DIR} // "$ENV{HOME}/.claude") . '/sessions';
    for my $file (glob "$dir/*.json") {
        open my $fh, '<', $file or next;
        my $j = do { local $/; <$fh> };
        close $fh;
        next unless index($j, $SID) >= 0;
        ($sname) = $j =~ /"name":"([^"]*)"/;
        $sname = clean($sname);
        last;
    }
}
my $cwd;
if (my $e = $META_CWD) { my $h = $ENV{HOME} // ''; utf8::decode($h); $e =~ s/^\Q$h\E(?=\/|$)/~/ if $h; $cwd = $e; }
# claudzilla version from the clone this script links into: the last release tag, or, when the
# clone runs ahead of it, the tag CI would cut next (same script as .github/workflows/test.yml)
my $ver;
{   my $hd = $CZ_HUD;
    $hd =~ s/'/'\\''/g if defined $hd;
    my $last = defined $hd ? `git -C '$hd' describe --tags --abbrev=0 --match 'v[0-9]*' 2>/dev/null` // '' : '';
    $last =~ s/\s+$//;
    if (length $last) {
        (my $q = $last) =~ s/'/'\\''/g;
        my $next = `git -C '$hd' log --format='%s%n%b' '$q..HEAD' 2>/dev/null | sh '$hd/../../.github/next-version.sh' '$q' 2>/dev/null` // '';
        $next =~ s/\s+$//;
        $ver = clean(length $next ? $next : $last);
    }
}
# branch + dirty from the session cwd; blank when not a repo
my ($branch, $dirty);
my $churn = '';
if ($META_CWD) {
    my $d = $META_CWD; $d =~ s/'/'\\''/g;
    $branch = `git -C '$d' branch --show-current 2>/dev/null` // ''; $branch =~ s/\s+\z//; $branch = clean($branch);
    $branch = undef unless length $branch;
    if ($branch) {
        my @st = split /\n/, (`git -C '$d' status --porcelain 2>/dev/null` // '');
        my $m = grep { !/^\?\?/ } @st; my $u = @st - $m;
        $dirty = join ' ', ($m ? "!$m" : ()), ($u ? "?$u" : ());
        my $st = `git -C '$d' diff --shortstat 2>/dev/null` // '';
        my ($ins) = $st =~ /(\d+) insertion/; my ($del) = $st =~ /(\d+) deletion/;
        $churn = join ' ', ($ins ? "+$ins" : ()), ($del ? "-$del" : ());
    }
}
my ($model, $session, $skill, $thinking) = @f{qw(model up skill thinking)};

my %mv = map { $_ => [$_, $f{$_}, $f{"${_}_note"} // ''] } grep { ($f{$_} // '') =~ /^\d+$/ } qw(ctx cch 5h wk);
# limits not in yet: blank meters keep the layout from jumping on the first reply. Note is 5 wide, mid-range for a reset time (2h5m to 23h59m).
if ($f{lim_wait}) { $mv{$_} //= [$_, undef, sprintf('%5s', '--')] for qw(5h wk) }

# --- helpers ---------------------------------------------------------------
# terminal cells: East Asian wide chars take two
sub vis { my $s = shift; $s =~ s/\e\[[0-9;]*m//g; return length($s) + (() = $s =~ /[\p{EA=W}\p{EA=F}]/g) }
sub pad {                       # left, right -> line padded to $W
    my ($l,$r,$fill) = @_; $fill //= ' ';
    my $gap = $W - vis($l) - vis($r); $gap = 1 if $gap < 1;
    return $l . "\e[2m" . ($fill x $gap) . "\e[0m" . $r;
}
sub fits { my ($l,$r) = @_; return vis($l) + vis($r) + ($r ne '' ? 2 : 0) <= $W }
sub paint {                     # [char, r, g, b] cells -> string, colour code only where it changes
    my ($out,$prev) = ('','');
    for (@_) {
        my ($ch,@c) = @$_;
        my $seq = "\e[38;2;" . join(';', map { int($_ + 0.5) } @c) . "m";
        $out .= ($seq eq $prev ? '' : $seq) . $ch;
        $prev = $seq;
    }
    return $out . "\e[0m";
}
my $WID = 10;   # highlight half-width in cells
# one solid colour per bar, by level: teal, orange from 70%, red from 90%
# meter titles in full; $LW fits the longest, so stacked bars line up
my %NAME = (cch => 'cache', ctx => 'context', wk => 'weekly');
my $LW = 7;
sub level { my $p = shift // 0; $p >= 90 ? [224,108,117] : $p >= 70 ? [245,167,66] : [86,182,194] }
# builds a whole meter row as cells, then runs the highlight across all of it -
# title, bar, figure and note alike. $head is the sweep centre, undef while resting.
sub meter_line {
    my ($label,$pct,$note,$n,$tw,$lw,$pw,@hs) = @_;
    my $wait = !defined $pct; $pct //= 0;
    my $f = int($pct / 100 * $n + 0.5); $f = $n if $f > $n;
    # cache is a clock, not a fill: a solid full bar
    my $cache = $label eq 'cch';
    $f = $n if $cache;
    my $cc = level($pct);
    my @cell;
    push @cell, [$_, [128,128,128]] for split //, sprintf('%-*s ', $lw, $NAME{$label} // $label); # title
    for my $i (0 .. $n-1) {                                                   # bar
        my $on = $i < $f;
        push @cell, [$cache ? $G_CACHE : $on ? $G_ON : $G_OFF,
                     $on ? $cc : [60,60,60],
                     $on ? 0.65 : 0.30];
    }
    my $fc = $wait ? [128,128,128] : $cc;                                     # figure
    push @cell, [$_, $fc] for split //, sprintf(' %*s%%  ', $pw, $wait ? '--' : $pct);
    push @cell, [$_, [128,128,128]] for split //, sprintf("%*s", $tw, $note);    # note
    my @px;
    for my $i (0 .. $#cell) {
        my ($ch,$c,$w) = @{$cell[$i]};
        $w //= 0.55;                                                          # text glows a touch less than fill
        my @c = @$c;
        my $g = 0;
        for my $h (@hs) { my $v = glow($i - $h, $WID, 1.6); $g = $v if $v > $g }
        @c = map { $c[$_] + (255 - $c[$_]) * ($g * $w) } 0..2 if $g > 0;
        push @px, [$ch, @c];
    }
    return paint(@px);
}
my $dim = sub { "\e[2m$_[0]\e[0m" };
# meter titles: muted lilac - clear of the teal profile and the blue->orange ramp

# per-session phase offset so concurrent sessions animate out of step
my $OFF = 0; $OFF = ($OFF * 31 + ord) % 3600 for split //, ($id // '');

my $row = 0;

my @out;

# identity: path + branch + session id, profile flush right
# cwd: one solid colour
sub cwd_str { "\e[38;2;127;216;143m$_[0]\e[0m" }
{   # narrow panes: shed the least important pieces, then trim the path itself
    my $path = $cwd // '~';
    my $p    = '';   # account email hidden
    my @opt = ( [$branch, sub { $dim->('  ') . "\e[38;2;92;156;245m$G_BRANCH $_[0]\e[0m" }],
                [$dirty,  sub { $dim->(' ')  . "\e[38;2;245;167;66m$_[0]\e[0m"  }],
                [$churn,  sub { $dim->('  ') . "\e[38;2;127;216;143m$_[0]\e[0m" }] );
    my $build = sub {
        my $l = cwd_str($path);
        for my $o (@opt) { $l .= $o->[1]->($o->[0]) if defined $o->[0] }
        my $r = $p ne '' ? "\e[38;2;95;158;168m$p\e[0m" : '';
        $r .= ($r ne '' ? $dim->('  ') : '') . "\e[38;2;250;178;131m$ver\e[0m" if defined $ver;
        return ($l, $r);
    };
    my $fits = sub { fits($build->()) };
    if (!$fits->()) { $ver = undef }                         # version first
    if (!$fits->()) { $p =~ s/\@.*// }                       # profile: local part only
    if (!$fits->()) { $p = '' }                              # ...then drop it
    for my $i (2,1,0) { last if $fits->(); $opt[$i][0] = undef }   # churn, dirty, branch
    if (!$fits->() && length($path) > 4) {                    # finally trim the path from the left
        my $room = $W - 1;
        if ($room > 2) { $path = substr($path, 1) while vis($path) > $room - 1; $path = "\x{2026}$path" }
    }
    my ($l,$r) = $build->();
    push @out, pad($l, $r);
}

my $note_w = sub { my $w = 0; for (grep { defined } @mv{@_}) { $w = length $_->[2] if length $_->[2] > $w } $w };
my $tw = $note_w->(qw(ctx cch 5h wk));
# two columns, ctx over cache | 5h over wk, when each half keeps a usable bar; else one meter per row.
# Each column right-aligns its own notes.
my @one = grep { defined } @mv{qw(ctx cch 5h wk)};
# a fixed note width of 5, not $tw: the row count must not flip as a reset countdown changes length
my $ONE = $f{compact} && @one && int(($W - 3 * $#one) / @one) - ($LW + 8) - 5 >= 8;
my $CL = int(($W - 3) / 2); my $CRW = $W - 3 - $CL;
my $TWO = !$ONE && ($mv{'5h'} || $mv{wk}) && $CL - ($LW + 8) - $tw >= 8;
my ($twl, $twr) = $TWO ? ($note_w->(qw(ctx cch)), $note_w->(qw(5h wk))) : ($tw, $tw);
# empty on one row: the sweep's fill-edge pulse then starts mid-row, so it reaches both ends
my @m = $ONE ? () : $TWO ? grep { defined } @mv{qw(ctx cch)} : @one;
my $n  = ($TWO ? $CL : $W) - ($LW + 1) - 5 - 2 - $twl;

# --- sweep -----------------------------------------------------------------
# One highlight pass every $SWEEP+$REST seconds, wall-clock driven so the timing
# holds however often the HUD renders. Each pass picks one of ten motions at
# random - the pick is a hash of the cycle number, so every render inside a
# given pass agrees on it without any stored state.
my $SWEEP = 30; my $REST = 60; my $LAG = 2;
my $CYC   = $SWEEP + $REST;
my $NOW   = time() + $OFF;
my $VAR   = ((int($NOW / $CYC) * 1103515245 + 12345) >> 7) % 10;
my $TAIL  = ($VAR == 6);        # trailing comet: asymmetric, needs a different shape

# distance from a head -> 0..1 brightness. $d is signed so the tail can drag behind.
sub glow {
    my ($d,$wid,$pw) = @_;
    if ($TAIL) {
        my ($head,$tail) = (0.5*$wid, 2.2*$wid);
        return $d > 0 ? ($d < $head ? (1 - $d/$head) ** 2.2 : 0)
                      : (-$d < $tail ? (1 + $d/$tail) ** 2.6 * 0.8 : 0);
    }
    $d = abs $d;
    return $d < $wid ? (1 - $d/$wid) ** $pw : 0;
}

# head positions on row $r (-1 = top rule, 0..2 = meters, 3 = bottom rule).
# empty while resting, or while a row is waiting its turn.
sub heads {
    return ();   # highlight sweep off
    my ($r) = @_;
    my $t = $NOW % $CYC;
    return () if $t >= $SWEEP;
    my $p    = $t / $SWEEP;
    my $full = $W + 2*$WID;                 # just clears both edges
    my $span = $W + 2*$WID + 12*$LAG;       # ...even for the last lagging row
    return (-$WID - $LAG + $p*$span - $r*$LAG)                    if $VAR == 0;  # diagonal comet
    return (-$WID + $p*$full)                                     if $VAR == 1;  # vertical wipe
    if ($VAR == 2) {                                                             # relay
        my $q = ($p - ($r+1)/5) * 5;
        return () if $q < 0 || $q > 1;
        return (-$WID + $q*$full);
    }
    return (-$WID + $p*$span - (8 - abs($r-1)*4))                 if $VAR == 3;  # chevron
    return (-$WID + $p*$span + sin($r*1.3 - $p*6)*10)             if $VAR == 4;  # ripple
    return (-$WID + $p*$full, $W + $WID - $p*$full)               if $VAR == 5;  # two heads
    return (-$WID + $p*($full+24) - $r*$LAG)                      if $VAR == 6;  # trailing comet
    if ($VAR == 7) {                                                             # ping-pong
        my $u = $p < 0.5 ? 2*$p : 2 - 2*$p;
        return (-$WID + $u*$full - $r*$LAG);
    }
    if ($VAR == 8) {                                                             # pulse from the fill edge
        my $edge  = ($r >= 0 && $r <= 2 && $m[$r]) ? 4 + int(($m[$r][1] // 0)/100*$n + 0.5) : $W/2;
        my $reach = $p * ($W/2 + $WID);
        return ($edge - $reach, $edge + $reach);
    }
    my $th = $p * 6.283185307;                                                   # spin
    return ($W/2 + ($W/2 + $WID) * cos($th) * (1 + ($r-1)*0.28));
}

# rule comet: the same highlight running the hairline rules, in step with the bars
# (top rule rides one row ahead of ctx, lower rule one row behind wk)
my $CWID = 6;   # comet reach, as in the original: soft ^2 falloff, no hard core
my @DAY = qw(Sun Mon Tue Wed Thu Fri Sat);
my @MON = qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec);
sub rule {
    my ($r,$label) = @_;
    $label //= '';
    my @hs = map { int($_ + 0.5) } heads($r);    # snap so exactly one cell is the head
    my $start = int(($W - length($label)) / 2);
    my @px;
    for my $i (0 .. $W-1) {
        my $g = 0;
        for my $h (@hs) { my $v = glow($i - $h, $CWID, 2); $g = $v if $v > $g }
        my $ch = "\x{2501}";
        my @b  = (72,72,72); my $w = 0.75;                  # hairline
        if (length $label && $i >= $start && $i < $start + length $label) {
            $ch = substr($label, $i - $start, 1);
            @b  = $ch eq ' ' ? (13,18,24) : (141,166,194);  # inset clock / date
            $w  = $ch eq ' ' ? 0 : 0.9;
        }
        push @px, [$ch, $g > 0 ? (map { $b[$_] + ([255,236,200]->[$_] - $b[$_]) * ($g*$w) } 0..2) : @b];
    }
    return paint(@px);
}
my @lt = localtime;
push @out, rule(-1) unless $f{compact};

my $DIV = " \e[38;2;72;72;72m\x{2503}\e[0m ";
if ($ONE) {
    @one = grep { defined } @mv{qw(cch ctx 5h wk)};     # the three usage fills sit together, the cache clock apart
    my $room = $W - 3 * $#one;
    my $x = 0;
    my @hs = heads(1);      # middle row: the spin's row scale is 1, so it reaches both ends
    my @cols;
    # same bar length in every column: shared label, figure and note widths, bar sized to the narrowest column
    my $nw = 0; for (@one) { (my $t = $_->[2]) =~ s/^ +//; $nw = length $t if length $t > $nw }
    my $bar = int($room / @one) - 5 - $LW - 3 - $nw;
    for my $i (0 .. $#one) {
        my $col = int($room * ($i + 1) / @one) - int($room * $i / @one);
        my ($label, $pct, $note) = @{$one[$i]};
        $note =~ s/^ +//;
        push @cols, meter_line($label, $pct, $note, $bar, $nw, $LW, 3, map { $_ - $x } @hs);
        $x += $col + 3;
    }
    push @out, join($DIV, @cols);
} elsif ($TWO) {
    # a missing meter leaves its slot blank
    my $nr = $CRW - ($LW + 1) - 5 - 2 - $twr;
    $n = $nr = $n < $nr ? $n : $nr;   # same bar length in both columns
    for my $i (0, 1) {
        my ($l, $r) = ($mv{(qw(ctx cch))[$i]}, $mv{(qw(5h wk))[$i]});
        my @hs = heads($row++);
        push @out, ($l ? meter_line(@$l, $n, $twl, $LW, 3, @hs) : ' ' x ($n + $LW + 8 + $twl))   # blank slot as wide as a meter
                 . $DIV
                 . ($r ? meter_line(@$r, $nr, $twr, $LW, 3, map { $_ - $CL - 3 } @hs) : ' ' x $CRW);
    }
} else {
    for my $r (@m) {
        my ($label,$pct,$note) = @$r;
        push @out, meter_line($label, $pct, $note, $n, $tw, $LW, 3, heads($row++));
    }
}

push @out, rule(3) unless $f{compact};

# activity: model, skill, thinking; uptime flush right
{   # same treatment as the identity row, measured on the rendered strings
    my $mo = $model;
    $mo .= "\e[38;2;128;128;128m  $EFFORT\e[0m" if defined $mo && $EFFORT;
    my @L = ( [$mo,       sub { "\e[38;2;238;238;238m$_[0]\e[0m" }],
              [$skill,    sub { "\e[38;2;128;128;128m$G_SKILL $_[0]\e[0m" }],
              [$thinking, sub { "\e[38;2;157;124;216m\x{25C7} thinking\e[0m" }] );
    my $clock;   # time and date hidden
    my @R = ( [$clock,    sub { "\e[38;2;128;128;128m$_[0]\e[0m" }],
              [undef,     sub { "\e[38;2;128;128;128m$_[0]\e[0m" }],   # session name hidden
              [undef,     sub { "\e[38;2;102;102;102m$_[0]\e[0m" }],   # session id hidden
              [undef,     sub { "\e[38;2;128;128;128mup $_[0]\e[0m" }] );   # session time hidden
    my $build = sub {
        my $j = $dim->('  ');
        return (join($j, map { $_->[1]->($_->[0]) } grep { $_->[0] } @L),
                join($j, map { $_->[1]->($_->[0]) } grep { $_->[0] } @R));
    };
    my $fits = sub { fits($build->()) };
    $R[0][0] = undef unless $fits->();                            # clock
    for my $i (2,1) { last if $fits->(); $L[$i][0] = undef }     # thinking, skill
    for my $i (2,1) { last if $fits->(); $R[$i][0] = undef }      # session id, then name
    $L[0][0] = undef unless $fits->();                            # model, last resort
    my ($ls,$rs) = $build->();
    push @out, pad($ls, $rs);
}

print join("\n", @out), "\n";

# Trace what the line shows, only when a field changed. State is compared before the writer is loaded, so an unchanged tick costs one small read.
eval {
    my %now = (branch => $branch, dirty => $dirty, churn => $churn, ver => $ver, cwd => $cwd, name => $sname, skill => $skill,
               model => $model, effort => $EFFORT, ctx => $f{ctx}, '5h' => $f{'5h'}, wk => $f{wk});
    delete @now{grep { !defined $now{$_} || $now{$_} eq '' } keys %now};
    my $dir = ($ENV{TMPDIR} || '/tmp') . '/claudzilla-rules';
    (my $sid = $SID // '') =~ s/[^\w-]//g;
    my $sf = "$dir/hud-" . (length $sid ? $sid : 'nosession');
    my %was;
    if (open my $fh, '<:utf8', $sf) { %was = map { /^([^\t]+)\t(.*)$/ ? ($1, $2) : () } split /\n/, do { local $/; <$fh> // '' }; close $fh; }
    my @chg = grep { ($now{$_} // '') ne ($was{$_} // '') } keys %{{ %now, %was }};
    if (@chg) {
        mkdir $dir;
        if (open my $fh, '>:utf8', $sf) { print $fh map { "$_\t$now{$_}\n" } sort keys %now; close $fh; }
        require("$CZ_HUD/../hooks/trace.pl");
        trace_write({ session => $sid, part => 'hud', event => 'hud.change',
                      data => { changed => { map { $_ => $now{$_} // '' } @chg }, prev => { map { $_ => $was{$_} } grep { exists $was{$_} } @chg } } });
    }
};
