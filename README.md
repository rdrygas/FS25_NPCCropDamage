# FS25 NPC Crop Damage

**NPC Crop Damage** extends the standard crop damage mechanism in *Farming Simulator 25* to fields owned by NPCs. If the player drives a vehicle into a crop that is susceptible to damage on such a field, the crops will be destroyed in the same way as on their own field, and the player’s farm will be charged for the cost of the damage.
The mod works exclusively for player-controlled vehicles and respects the game setting **Crop Destruction**.

## Concept

The mod has been designed to be as minimal an extension of the base game’s mechanics as possible:

- it does not replace the standard `WheelDestruction` system;
- it does not alter the behaviour of crop destruction on fields belonging to the player;
- it extends its effect solely to NPC fields, i.e. agricultural land without an owner that is not part of the player’s farm;
- it only works if **Crop Destruction** is enabled in the game settings;
- it only works for vehicles actually driven by the player;
- it ignores AI workers;
- it respects maintenance tyres / wheels that the base game does not treat as damaging to crops;
- it destroys only those types and growth stages of crops that the base game designates as susceptible to damage from wheels;
- it does not force the destruction of root crops that are not subject to this mechanism in the standard game, including potatoes, sugar beet and beetroot.

## How the mod works

The script is attached to the standard `WheelDestruction:update()` function. The base game first handles the wheel itself, and the mod only runs an additional processing path if the wheel is on an NPC tile.

Before changing the state of the crops, the script checks the crop density map and counts only those pixels that are still in a state susceptible to destruction. Only then is the game’s standard function responsible for destroying the crop called.

This approach has two advantages:

1. it preserves the destruction rules defined by the game or the map;
2. it prevents multiple calculations of compensation for the same, already destroyed section of the crop.

## Calculating the cost of damage

By default, the cost is calculated using the following formula:

```text
cost = area of new damage [m²]
      × potential yield [l/m²]
      × highest current selling price [currency/l]
      × PENALTY_MULTIPLIER
```

Script:

1. determines the newly damaged crop area;
2. retrieves `literPerSqm` for the given crop type;
3. searches for the highest current price of the given product at available retail outlets;
4. multiplies the result by a configurable penalty factor;
5. totals the small amounts and periodically charges them to the player’s farm.

The cost is visible in the finances as **NPC crop damage**.

### Simplification of the cost model

`literPerSqm` represents the base potential yield for a given crop type. The model does not currently attempt to replicate the actual yield of a specific section of a field resulting, for example, from fertilisation, weeds, liming, ploughing or a Precision Farming system.

Compensation is therefore an estimated value of the potentially lost yield, rather than an exact forecast of the harvest from a given location.

## Behaviour Table

| Situation | Crop destruction | Financial penalty |
|---|:---:|:---:|
| Own field, standard wheels | As per the game | Not via this mod |
| NPC field, standard wheels, vulnerable crop | Yes | Yes |
| NPC field, cultivation tyres | no | no |
| NPC field, AI worker | not via this mod | no |
| NPC field, ‘Crop Destruction’ disabled | no | no |
| NPC field, already damaged section | no new damage | no |
| NPC field, potatoes | no* | no |
| NPC field, sugar beet | no* | no |
| NPC field, red beetroot | no* | no |

\* The mod respects the base game’s definitions. If a particular crop type does not have states marked as susceptible to damage from wheels, the mod does not force it to be damaged.

## Configuration

The most important settings are at the start of the file:

```lua
scripts/NPCCropDamage.lua
```

### Amount of compensation

```lua
NPCCropDamage.PENALTY_MULTIPLIER = 1.0
```

Examples:

- `0.5` — 50% of the estimated value of the damage;
- `1.0` — 100% of the estimated value of the damage;
- `2.0` — 200% of the estimated value of the damage.

### Diagnostics

```lua
NPCCropDamage.DEBUG = false
```

After changing this to:

```lua
NPCCropDamage.DEBUG = true
```

the mod logs additional diagnostic information to the `log.txt` file, including the area affected by damage, potential yield, price and the calculated cost.

## Installation

Copy the archive:

```text
FS25_NPCCropDamage.zip
```

to the following folder:

```text
Documents/My Games/FarmingSimulator2025/mods
```

Then enable the mod when loading your save file.

## Compatibility

This mod is a script-based mod designed for **Farming Simulator 25** and utilises the standard `WheelDestruction` mechanism.

The current version has been developed based on the FS25 scripting API **v1.20.0.0**.
The mod is intended for single-player gameplay. `modDesc.xml` is configured as follows:

```xml
<multiplayer supported='false'/>
```

## Change log

### 1.0.0.0

- first version;
- standard crop damage caused by wheels has been extended to NPC fields;
- limited the effect to player-controlled vehicles;
- added calculation of compensation based on the area of damage, `literPerSqm` and the highest current selling price;
- added the `PENALTY_MULTIPLIER` coefficient;
- added the financial entry “NPC crop damage”.