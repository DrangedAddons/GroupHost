# GroupHost

A World of Warcraft addon for WoW Forever. It shows where each group in the Looking For Group window is hosted and lets you list only groups from the locations you pick, so you can find low-ping groups.

Early version. It is being tested, and two things are still unconfirmed: that a dungeon is hosted on the group leader's realm, and that realm labels shared between players reach other realms.

## Features
- **Host tag:** each group row gets a tag after the dungeon name, such as `AU1` or `US2`. Green is your own location, orange is another. A tag ending in `?` is a guess from a nearby realm ID. Grey `#1234` is a realm nobody has labelled yet.
- **Hosts filter:** a "Hosts" dropdown at the bottom of the window, between Send Message and Group Invite. Tick the locations you want listed. Saved per character.
- **Tooltip line:** a "Host:" box under the group tooltip, with the realm ID and, once you have run a dungeon with a leader from that realm, your measured ping.
- **Learns realms:** Forever hides realm names, but every listing carries its leader's realm ID. The addon learns your own realm's name at login and shares known realms with group and guild members who also run it. The more people on different realms run it, the fewer guesses.

## Using it
- `/gh` (or `/grouphost`), the minimap button, the addon list button or Options > AddOns > GroupHost opens the settings.
- `/gh set <realm id> <datacenter>` labels a realm by hand, for example `/gh set 6936 US2`. `/gh forget <realm id>` removes your label.
- `/gh list` prints the realms it knows.
- `/gh debug` saves a description of the Looking For Group window to the saved variables, for bug reports.

## Installing
Put the folder in `World of Warcraft\_forever_\Interface\AddOns` and make sure it is named `GroupHost`. Restart the game; a `/reload` does not load a new addon.

## Reporting a problem
Send a screenshot of the Looking For Group window and, after a `/reload`, the file `WTF\Account\<account>\SavedVariables\GroupHost.lua`.

Includes LibStub, CallbackHandler, LibDataBroker and LibDBIcon (see Libs).

Icon: ability_hunter_pathfinding from Wowhead, scaled up by `tools/make_icon.py`.
