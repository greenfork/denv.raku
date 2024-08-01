use v6.d;

use Point;
use Terminal::ReadKey;

use lib ".";
use Surfaces;

class World { ... };
class Wall { ... };

class Object {
    has Int:D $.ID is built(False) = self!next-id;

    method Str { self.^name ~ "|" ~ (self.defined ?? $!ID !! "UNDEF") }
    method gist { self.Str }

    method update-pos (World:D $w, Point:D $new-pos) {
        self.pos = $new-pos;
        for $w.board.cells.values -> $cell is rw {
            if $cell.object.defined and $cell.object.ID == self.ID {
                $cell.object = Nil;
                last;
            }
        }
        $w.board.cells{$new-pos}.object = self;
    }

    my atomicint $ID = 1;
    method !next-id { $ID⚛++ }
}

role Movable {
    method try-move-left (World $w) { self!try-move: $w, { self.left-cell($w) }, { self.left } }
    method try-move-right (World $w) { self!try-move: $w, { self.right-cell($w) }, { self.right } }
    method try-move-up (World $w) { self!try-move: $w, { self.up-cell($w) }, { self.up } }
    method try-move-down (World $w) { self!try-move: $w, { self.down-cell($w) }, { self.down } }

    method !try-move ($w, &cell, &coord) {
        return unless self.pos.defined;
        unless self.consume-move-points(5) {
            $w.current-message = "Not enough move points";
            return;
        }

        my $cell = cell;
        if $cell.can-move-to {
            self.update-pos: $w, coord;
            self.effect-from-surface: $cell.surface;
        } else {
            self.commentary = "I can't move there!";
        }
    }
}

class Creature is Object does EffectsOnCreature does Movable {
    has Int $.health;
    has Int $.move-points;
    has Int $.action-points;
    has Int $!max-health;
    has Int $!max-move-points;
    has Int $!max-action-points;

    submethod TWEAK (:$health, :$move-points, :$action-points) {
        $!max-health = $health;
        $!max-move-points = $move-points;
        $!max-action-points = $action-points;
    }

    proto method damage (Int :$) { * }
    multi method damage (:$melee!) {
        say "Getting hit by $melee melee damage!";
        $!health -= $melee;
    }
    multi method damage (:$fire!) {
        if self.find-effect(MagicArmorEffect) {
            say "Magic armor blocks $fire fire damage!";
            return;
        }

        say "Getting $fire fire damage!";
        $!health -= $fire;
    }
    multi method damage (:$poison!) {
        say "Getting poisoned by $poison points!";
        $!health -= $poison;
    }
    multi method damage (:$blast!) {
        say "Getting $blast points of damage from a blast!";
        $!health -= $blast;
    }

    method replenish {
        $!move-points = $!max-move-points;
        $!action-points = $!max-action-points;
    }

    method consume-action-points (Int \n --> Bool) {
        if $!action-points - n >= 0 {
            $!action-points -= n;
            True;
        } else {
            False;
        }
    }

    method consume-move-points (Int \n --> Bool) {
        if $!move-points - n >= 0 {
            $!move-points -= n;
            True;
        } else {
            False;
        }
    }

    method exhaust-move-points (Int \n) {
        with n {
            $!move-points = max(0, $!move-points - n);
        } else {
            $!move-points = 0;
        }
    }

    method draw-effects {
        self.effects.map: {
            my $d = $_.duration;
            when BurningEffect { "🔥($d)" }
            when WetEffect { "💧($d)" }
            when WarmEffect { "☕($d)" }
            when ChilledEffect { "($d)" }
            when FrozenEffect { "⛄($d)" }
            when MagicArmorEffect { "🧙($d)" }
            when PoisonedEffect { "💚($d)" }
            when CursedEffect { "💀($d)" }
        }
    }
}

role OnBoard {
    has Point:D $.pos is rw is required;

    method left { self.pos + point(0,-1) }
    method right { self.pos + point(0,1) }
    method up { self.pos + point(-1,0) }
    method down { self.pos + point(1,0) }

    method my-cell (World $w) { $w.board.cells{self.pos} }
    method left-cell (World $w) { $w.board.cells{self.left} }
    method right-cell (World $w) { $w.board.cells{self.right} }
    method up-cell (World $w) { $w.board.cells{self.up} }
    method down-cell (World $w) { $w.board.cells{self.down} }
    method around-cells (World $w) {
        self.left-cell($w), self.up-cell($w), self.right-cell($w), self.down-cell($w);
    }
}

class Player is Creature does OnBoard does EffectComments {
    has Str $.commentary is rw = "";

    method draw { "@" }

    method pour-water (World $w) {
        unless self.consume-action-points(2) {
            $w.current-message = "Not enough action points";
            return;
        }
        all(self.around-cells($w)).apply: WaterElement.new, $w;
    }

    method throw-poison (World $w) {
        unless self.consume-action-points(3) {
            $w.current-message = "Not enough action points";
            return;
        }
        all(self.around-cells($w)).apply: PoisonElement.new, $w;
    }

    method curse-around (World $w) {
        all(self.around-cells($w)).apply: CurseElement.new, $w;
    }

    method draw-commentary {
        my $m = $!commentary;
        $!commentary = "";
        $m;
    }
}

class Cell does OnBoard {
    has Surface:D $.surface is rw = EmptySurface.instance;
    has $.cloud is rw = EmptyCloud.instance;
    has Object $.object is rw;

    method draw (|c) { !!! }
    method draw-object returns Str {
        with $!object { .draw }
        else { Nil }
    }
    method draw-surface returns Str {
        with $!surface { .draw }
        else { Nil }
    }
    method draw-cloud returns Str {
        with $!cloud { .draw }
        else { Nil }
    }

    method can-move-to { !!! }

    method apply (Element:D $e, World:D $w) {
        for $!surface.apply: $e {
            when Element { self.apply($_, $w) }
            when StateChange { self.apply-state-change($_) }
            when EnvironmentEffect { $w.apply-environment-effect($_, self) }
        }
        # TODO: how to apply e.g. wind to both surface and cloud? The sequence
        # will be wrong if wind creates clouds from surface and then also
        # removes clouds.
        # $!cloud.apply: $e;
    }

    method apply-state-change (StateChange:D $sc) {
        $!surface = $sc.to-surface;
        $!cloud = $sc.to-cloud;
    }
}

class Empty is Cell {
    my Empty $instance;
    method new {!!!}
    submethod instance {
        $instance = Empty.bless(:pos(point(-1,-1))) unless $instance;
        $instance;
    }
    method draw (|c) { " " }
}
class Floor is Cell {
    method draw (|c) {
        self.draw-object or self.draw-cloud or self.draw-surface;
    }

    method can-move-to { True }
};
class Wall is Cell {
    method draw (|c (Cell $left, Cell $up, Cell $right, Cell $down)) {
        sub isw ($cell) { $cell ~~ Wall }

        if isw($down & $right) { "╔" }
        elsif isw($down & $left) { "╗" }
        elsif isw($up & $right) { "╚" }
        elsif isw($up & $left) { "╝" }
        elsif isw($left | $right) { "═" }
        elsif isw($up | $down) { "║" }
        else { "╥" }
    }

    method can-move-to { False }
};
class Door is Wall {
    has $.open = False;

    method draw (|c) { "O" }

    method can-move-to { $!open }
};

class Board {
    has Cell %.cells{Point} is default(Empty.instance);

    method draw {
        (1..10 X 1..20).map(-> ($x, $y) {
            my $point = point($x, $y);
            my $cell = %!cells{$point}.draw: |%!cells{self!neighbours($point)};
            if $y == 20 and $x != 10 {
                $cell ~ "\n";
            } else {
                $cell;
            }
        }).join
    }

    method !neighbours ($point) {
        $point + point( 0,-1),
        $point + point(-1, 0),
        $point + point( 0, 1),
        $point + point( 1, 0);
    }

    method replace-cell (Point:D $pos, Cell:D $cell) {
        self.cells{$pos} = $cell;
    }
}

constant $map = q:to/MAP/;
╔════╗
O....║
║..@.║
╚╗.ff║
 ╚═══╝
MAP

grammar BoardGrammar {
    token TOP {
    :my $*LINE = 1;
    :my $*COL = 1;
    [
        [ <wall> | <door> | <player> | <floor> | <fire> | <.newline> | <.space> ]
        <.succ>
    ]+ }
    token wall { < ╔ ║ ╝ ═ ╚ ╗ > }
    token door { O }
    token player { "@" }
    token floor { "." }
    token fire { f }
    token space { " " }
    token newline { "\n" { $*LINE++; $*COL = 0; } }
    token succ { <?> { $*COL++ } }
}

class BoardActions {
    has Board:D $!board .= new;
    has Player:D $.player is required;

    method TOP ($/) { make $!board }
    method wall ($/) { self!add: Wall.new(:pos(self!point)) }
    method door ($/) { self!add: Door.new(:pos(self!point)) }
    method floor ($/) { self!add: Floor.new(:pos(self!point)) }
    method fire ($/) { self!add: Floor.new(surface => FireSurface.new, :pos(self!point)) }
    method player ($/) {
        $!player.pos = self!point;
        self!add: Floor.new(object => $!player, :pos(self!point));
    }

    method !add (Cell:D $cell) {
        $!board.cells{self!point} = $cell;
    }
    method !point { point($*LINE, $*COL) }
}

role WorldControl {
    proto method control (Str $key) { * }
    multi method control ("Left") { self.player.try-move-left(self) }
    multi method control ("Right") { self.player.try-move-right(self) }
    multi method control ("Up") { self.player.try-move-up(self) }
    multi method control ("Down") { self.player.try-move-down(self) }
    multi method control ("p") { self.player.pour-water(self) }
    multi method control (".") { self.next-round }
    multi method control ("m") { self.player.add-effect: MagicArmorEffect.new(:2duration) }
    multi method control ("e") { self.player.throw-poison(self) }
    multi method control ("c") { self.player.curse-around(self) }
    multi method control (Str) {}
}

role SurfaceDegradation {
    method tick-surfaces {
        for self.board.cells.values.grep(*.surface !~~ EmptySurface) -> $cell is rw {
            if --$cell.surface.duration == 0 {
                $cell.apply-state-change: $cell.surface.time-out;
            }
        }
    }
}

role EnvironmentEffectsOnWorld {
    proto method apply-environment-effect (EnvironmentEffect:D, Cell) { * }
    multi method apply-environment-effect (ExplosionEnvironmentEffect:D $e, Cell:D $cell) {
        #  .
        # ...
        #  .
        my @small-circle = $cell, |$cell.around-cells(self);

        #   .
        #  ...
        # .....
        #  ...
        #   .
        my @large-circle = @small-circle.flatmap(*.around-cells(self)).unique(:as(*.pos));

        for @small-circle {
            # Wall is destructed and turns into smoke.
            when Wall { self.board.replace-cell: .pos, Floor.new(cloud => SmokeCloud.new, :pos(.pos)) }
            # Small circle gets affected by fire.
            when Floor {
                .apply: FireElement.new, self;
                .apply-effect: BurningEffect.new(:3duration) with .object;
            }
        }
        for @large-circle {
            # Large circle gets a blast wave.
            when Floor {
                with .object {
                    when Creature { .damage: :5blast }
                }
            }
        }
    }
}

class World does WorldControl does EnvironmentEffectsOnWorld does SurfaceDegradation {
    has Board:D $.board is required;
    has Player:D $.player is required;
    has Str:D $.current-message is rw = "";
    has Int:D $.round = 1;

    method draw {
        $!board.draw
    }

    method draw-stats {
        qq｢Round: {$!round}  Health: {$!player.health}  Move points: {$!player.move-points}  Action points: {$!player.action-points}  Effects: {$!player.draw-effects}｣
    }

    method draw-current-message {
        my $m = $!current-message;
        $!current-message = "";
        $m;
    }

    method next-round {
        $!player.replenish;
        $!player.tick-effects;
        $!player.effect-from-surface: $!player.my-cell(self).surface;
        self.tick-surfaces;
        $!round++;
    }
}

constant INSTRUCTIONS = q:to/INS/;
Press arrows to move
Press . to finish your turn
Press e to throw poison around
Press p to pour water around
Press m to get magic armor
Press c to curse cells around
Press Ctrl+D to finish the game
INS

sub MAIN {
    my $player = Player.new(:10health, :30move-points, :3action-points, :pos(point(-1,-1)));
    my $world = World.new(
        board => BoardGrammar.parse($map, actions => BoardActions.new(:$player)).made,
        :$player,
    );

    say INSTRUCTIONS;

    say $world.draw;
    say $world.draw-stats;
    say $world.draw-current-message;
    react {
        whenever key-pressed() {
            when "Ctrl D" { last }
            say "=" x 80;
            say "Pressed $_";
            $world.control: $_;
            say $world.draw;
            say $world.draw-stats;
            say $world.draw-current-message;
            say $player.draw-commentary;

            if $player.health <= 0 {
                say "YOU DED";
                last;
            }
        }
    }
}
