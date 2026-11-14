# Changelog

## 0.1.3

- New icon: a compass, in place of the map icon VendorPoint already uses.

## 0.1.2

- Fixed groups from unticked locations still showing in the Looking For Group window. The list is now redrawn after it is filtered, and any unticked group that reaches the screen later (the game adds groups to an open list) is taken out.

## 0.1.1

- Fixed nothing showing on WoW Forever. Its Looking For Group window is the classic-style browse frame, and 0.1.0 only hooked retail's group finder. The host tag, the Hosts dropdown (between Send Message and Group Invite) and the host line under the group tooltip now attach to that window.
- Saves a description of the browse window to `GroupHostDB.debug` on the first list each session (`/gh debug` does it on demand), for fixing layout problems.

## 0.1.0

- Host tag on each group finder listing, read from the realm ID in the listing's party GUID. Green is your own location, orange is another, grey is an unknown realm. A tag ending in `?` is a guess from a nearby realm ID.
- "Hosts" dropdown on the search panel to list only groups hosted in the locations you tick. Saved per character.
- Host line in listing tooltips, with your measured instance ping for that realm once you have run a dungeon with a leader from it.
- Works with EllesmereUI's group finder list and with the stock list.
- Learns your own realm from its name and shares known realms with group and guild members who run GroupHost. `/gh set <realm id> <datacenter>` labels a realm by hand.
- Built-in realms: 6801 (AU1), 6936 (US2).
