# Kilocrypt

A first-person horror shooter under 16 KB: fight through six floors of a dark facility, restoring power with fuses, then escape.

## Campaign

**Floor**:
One level of the facility, played until the player takes the powered exit. Six floors make a loop. Floors keep counting across loops: floor 7 is the first floor of the second loop.
_Avoid_: Level, stage, map

**Loop**:
One pass through all six floors. After the ending, the next loop repeats the floors harder.
_Avoid_: New game plus, cycle

**Fuse**:
One of three objects per floor that must be collected to power the exit.
_Avoid_: Key, battery

**Alarm**:
What picking up a fuse sets off: nearby monsters wake and rush the player, reaching further with each fuse until the third wakes the whole floor.
_Avoid_: Lockdown, shutdown

**Exit**:
The pad that ends the floor once all three fuses are in.
_Avoid_: Door, goal

## Weapons

**Shotgun**:
The starting gun. It never runs out of ammo.

**Minigun**:
A multi-barrel gun that spins up before it fires.

**Rocket launcher**:
Fires rockets that explode where they hit.
_Avoid_: Bazooka

**Plasma rifle**:
The fourth gun. Fires a stream of glowing plasma bolts that travel and burst on impact; its alt fire is a shockwave around the player. It replaced the rail gun.
_Avoid_: Rail gun, laser gun, laser

**Upgrade**:
One of two permanent improvements per gun, dropped by a guardian: the first unlocks the gun's alt fire, the second is one large boost. Upgrades from earlier floors survive death; those from the current floor do not.
_Avoid_: Powerup, perk

**Alt fire**:
The right-click attack every gun has, unlocked by that gun's first upgrade.
_Avoid_: Secondary, special

## Space

**Cell**:
One 20 m square of the floor's 4×4 grid.
_Avoid_: Tile, square

**Room**:
A walled space made of one or more connected cells.
_Avoid_: Area, chamber, cell

**Room kind**:
The theme of a room (morgue, storage, boiler, pump hall, flooded catwalk) that sets its furniture, surfaces and lamp colour.
_Avoid_: Room type, biome

## Threats

**Guardian**:
A monster placed at a fuse to defend it.
_Avoid_: Fuse guard, mini-boss

**Lead monster**:
The monster type that defines a floor: it guards that floor's fuses and leads its chase waves.
_Avoid_: Signature monster, floor enemy

**Sleeper**:
A monster that waits in place until it notices the player.
_Avoid_: Idle monster, dormant

**Hunter**:
The floor-4 monster that stalks the player from the start of the floor and cannot be hurt until the third fuse.
_Avoid_: Stalker, floor-4 brute

**Clinger**:
A monster hanging from the ceiling that drops when the player comes near.
_Avoid_: Ceiling crawler, dropper

**Chase wave**:
A pack that spawns out of sight behind the player after a warning (stuttering lights and a distant howl).
_Avoid_: Spawn wave, horde

**Ambush wave**:
A silent pack of clingers placed in a hidden room ahead of the player.
_Avoid_: Trap, surprise wave

**Frenzy**:
The kill-chain state: consecutive player kills speed up firing and heal at close range.
_Avoid_: Combo, streak
