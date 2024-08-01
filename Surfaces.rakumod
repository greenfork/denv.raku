use v6.d;

unit module Surfaces;

class Surface { ... }
class Cloud { ... }
class EmptySurface { ... }
class EmptyCloud { ... }
class WaterSurface { ... }
class PoisonSurface { ... }
class StateChange { ... }
class Element { ... }
class FireElement { ... }
class WaterElement { ... }
class IceElement { ... }
class PoisonElement { ... }
class OilElement { ... }

enum MagicState <Cursed Neutral Blessed>;

role Enchantable {
    has MagicState $.magic-state = Neutral;

    method is-cursed { $!magic-state eqv Cursed }
    method is-blessed { $!magic-state eqv Blessed }
    method is-magical { $.is-cursed or $.is-blessed }
    method curse {
        given $!magic-state {
            when * eqv Cursed {}
            when * eqv Neutral { $!magic-state = Cursed }
            when * eqv Blessed { $!magic-state = Neutral }
        }
    }
    method bless_ {
        given $!magic-state {
            when * eqv Cursed { $!magic-state = Cursed }
            when * eqv Neutral { $!magic-state = Blessed }
            when * eqv Blessed {}
        }
    }
}

#| Some elements correspond to certain surfaces.
my Surface:U %element-to-surface{Element:U} =
    ::WaterElement => WaterSurface,
    ::PoisonElement => PoisonSurface,
;

#| Some surfaces correspond to certain elements.
my Element:U %surface-to-element{Surface:U} = %element-to-surface.antipairs;

#| Index defines a priority, from lowest to highest.
my Surface:U @surface-priorities = [
    WaterSurface,
    PoisonSurface,
];

#| A list of all elements that can be substituted by other elements.
my @surface-solution-elements =
        @surface-priorities.map: { %surface-to-element{$_} };

class Effect is export {
    has Int $.duration is rw = 1;
}
class WetEffect is Effect is export {}
class BurningEffect is Effect is export {}
class ChilledEffect is Effect is export {}
class WarmEffect is Effect is export {}
class FrozenEffect is Effect is export {}
class MagicArmorEffect is Effect is export {}
class PoisonedEffect is Effect is export {}
class CursedEffect is Effect is export {}

class Element does Enchantable is export {
    method to-surface {
        %element-to-surface{self.WHAT}.new: :magic-state($.magic-state);
    }
}
class FireElement is Element is export {}
class WaterElement is Element is export {}
class IceElement is Element is export {}
class PoisonElement is Element is export {}
class OilElement is Element is export {}
class ElectricityElement is Element is export {}
class BlessElement is Element is export {}
class CurseElement is Element is export {}

class EnvironmentEffect is export {}
class ExplosionEnvironmentEffect is EnvironmentEffect is export {}

role Solution {
    multi method apply (Element:D $e where $e.WHAT ⊂ @surface-solution-elements) {
        my $new-surface := $e.to-surface;
        if will-substitute(self, $new-surface) {
            StateChange.surface($new-surface);
        }
    }

    sub will-substitute (Surface:D $from, Surface:D $to) returns Bool {
        return False if $from.WHAT ~~ $to.WHAT;

        my $diff = priority-difference $from, $to;
        my $magic-multiplier =
            do if $from.is-magical and !$to.is-magical { -1 }
            elsif !$from.is-magical and $to.is-magical { 1 }
            else { 0 }
        my $chance = .4 + .2×$diff + .5×$magic-multiplier;
        rand < $chance;
    }

    sub priority-difference ($from, $to) returns Int {
        surface-priority($to) - surface-priority($from);
    }

    sub surface-priority ($surface where $surface.WHAT ⊂ @surface-priorities) returns Int {
        @surface-priorities.first(* ~~ $surface.WHAT, :k);
    }
}

class NoEffect is Effect is export {
    my NoEffect $instance;
    method new {!!!}
    submethod instance {
        $instance = NoEffect.bless unless $instance;
        $instance;
    }
}

role EffectComments is export {
    proto method comment-on-effect (Effect) { * }
    multi method comment-on-effect (BurningEffect) { self.commentary = "Ouch, it burns!" }
    multi method comment-on-effect (WetEffect) { self.commentary = "I'm wet now..." }
    multi method comment-on-effect (WarmEffect) { self.commentary = "Feels warm" }
    multi method comment-on-effect (ChilledEffect) { self.commentary = "I'm freezing..." }
    multi method comment-on-effect (FrozenEffect) { self.commentary = "Argh..." }
    multi method comment-on-effect (PoisonedEffect) { self.commentary = "I'm poisoned!" }
}

class StateChange is export {
    has Surface:D $.to-surface = EmptySurface.instance;
    has Cloud:D $.to-cloud = EmptyCloud.instance;

    submethod new { !!! }
    method empty { self.bless }
    method surface (Surface $surface) { self.bless: :to-surface($surface) }
    method cloud (Cloud $cloud) { self.bless: :to-cloud($cloud) }

    method Str { "StateChange|surface={$!to-surface // 'None'};cloud={$!to-cloud // 'None'}" }
}

class Cloud does Enchantable is export {
    has Numeric $.duration is rw = ∞;

    submethod new { ... }
    method draw { ... }
    method time-out { StateChange.cloud(EmptyCloud.instance) }
}

class EmptyCloud is Cloud is export {
    my EmptyCloud $instance;
    method new {!!!}
    submethod instance {
        $instance = EmptyCloud.bless unless $instance;
        $instance;
    }

    method draw { Nil }
    multi method apply (Effect:D) {}
}

class SmokeCloud is Cloud is export {
    method draw { $.is-cursed ?? "S" !! "s" }
}

class SteamCloud is Cloud is export {
    method draw { $.is-cursed ?? "T" !! "t" }
}

class Surface does Enchantable is export {
    has Numeric $.duration is rw = ∞;

    submethod new { ... }
    method draw { ... }
    method time-out { StateChange.surface(EmptySurface.instance) }

    proto method apply (Element) { * }
    multi method apply (CurseElement:D) { self.curse }
    multi method apply (BlessElement:D) { self.bless_ }
    multi method apply (Element $e) {
        die "Calling {self.^name}#apply($e)";
    }
}

class FireSurface is Surface is export {
    has Numeric $.duration is rw = 3;

    method draw { $.is-cursed ?? "F" !!  "f" }

    method time-out { StateChange.cloud(SmokeCloud.new: :magic-state($.magic-state)) }

    multi method apply (Element:D $e where $e ~~ WaterElement | IceElement) {
        if (self & $e).is-blessed {
            StateChange.cloud(SteamCloud.new: :magic-state(Blessed))
        } elsif (self & $e).is-cursed {
            StateChange.cloud(SteamCloud.new: :magic-state(Cursed))
        } elsif all(self, $e).is-magical or none(self, $e).is-magical {
            StateChange.cloud(SteamCloud.new)
        }
    }
    multi method apply (PoisonElement) { [StateChange.empty, ExplosionEnvironmentEffect.new] }
    multi method apply (FireElement) {}
}

class IceSurface is Surface is export {
    method draw { "~" }

    method time-out {}

    multi method apply (WaterElement) {}
    multi method apply (IceElement) { StateChange.surface(IceSurface.new) }
}

class WaterSurface is Surface does Solution is export {
    method draw { "~" }

    method time-out {}

    multi method apply (IceElement) { StateChange.surface(IceSurface.new) }
    multi method apply (FireElement) { StateChange.cloud(SteamCloud.new) }
}

class PoisonSurface is Surface does Solution is export {
    method draw { "P" }

    method time-out {}

    multi method apply (PoisonElement) {}
    multi method apply (IceElement) {}
    multi method apply (FireElement) { [StateChange.empty, ExplosionEnvironmentEffect.new] }
}

class EmptySurface is Surface is export {
    my EmptySurface $instance;
    method new {!!!}
    submethod instance {
        $instance = EmptySurface.bless unless $instance;
        $instance;
    }

    method draw { "." }
    multi method apply (WaterElement) { StateChange.surface(WaterSurface.new) }
    multi method apply (PoisonElement) { StateChange.surface(PoisonSurface.new) }
    multi method apply (Element:D $e where $e.WHAT !~~ CurseElement & BlessElement) {}
}

role EffectsOnCreature is export {
    has Effect:D @.effects = [];

    proto method effect-from-surface (Surface:D) { * }
    multi method effect-from-surface (EmptySurface:D) {}
    multi method effect-from-surface (FireSurface:D $s) {
        self.add-effect: BurningEffect.new(:3duration);
        self.remove-effect: WetEffect;
        self.damage: :3fire;
        self.comment-on-effect: BurningEffect;
        self.exhaust-move-points: 10;
    }
    multi method effect-from-surface (FireSurface:D $s where $s.is-cursed) {
        self.add-effect: CursedEffect.new(:3duration);
        nextsame;
    }
    multi method effect-from-surface (WaterSurface:D $s) {
        with self.find-effect(BurningEffect) {
            self.remove-effect: BurningEffect;
            self.add-effect: WarmEffect.new;
            self.comment-on-effect: WarmEffect;
        } orwith self.find-effect(ChilledEffect) {
            self.remove-effect: ChilledEffect;
            self.add-effect: FrozenEffect.new(:2duration);
            self.comment-on-effect: ChilledEffect;
        } else {
            self.add-effect: WetEffect.new(:3duration);
            self.comment-on-effect: WetEffect;
        }
    }
    multi method effect-from-surface (PoisonSurface:D $s) {
        self.add-effect: PoisonedEffect.new(:3duration);
        self.comment-on-effect: PoisonedEffect;
    }

    method add-effect (Effect:D $e) {
        self.remove-effect($e.WHAT) with self.find-effect($e.WHAT);
        @!effects.push: $e;
    }
    method find-effect (Effect:U $effect-type) { @!effects.first(* ~~ $effect-type) }
    method remove-effect (Effect:U $effect-type) {
        @!effects.splice($_, 1) with @!effects.first(* ~~ $effect-type, :k);
    }

    method tick-effects {
        @!effects .= map: -> $effect {
            self.apply-effect: $effect;
            --$effect.duration <= 0 ?? Empty !! $effect;
        }
    }

    proto method apply-effect (Effect:D) { * }
    multi method apply-effect (BurningEffect:D) { self.damage: :3fire }
    multi method apply-effect (PoisonedEffect:D) { self.damage: :3poison }
    multi method apply-effect (WarmEffect:D) {}
    multi method apply-effect (WetEffect:D) {}
    multi method apply-effect (ChilledEffect:D) {}
    multi method apply-effect (FrozenEffect:D) { self.exhaust-move-points }
    multi method apply-effect (MagicArmorEffect:D) {}
    multi method apply-effect (CursedEffect:D) {}
}
