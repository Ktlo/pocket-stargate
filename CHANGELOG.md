## v1.2.0 2025-01-08

### Added
- Stargate interface energy capacity becomes visible in PSG.
- All programs show their versions now. PSG and SSG will also show SGS version.
- PSG will show feedback messages even if SGS uses basic interface.
- SSG can show key names now.
- Audit entry will show key name for 'auth' event if possible.
- You can specify your key name in Keys menu in PSG. This name will be sent to SSG on key exchange.
- Your key name is stored in *public_key.txt* file. *keyring.txt* and *public_key.txt* files now have the same format.
- You can specify alternative local stargate address for SGS. This can be used to hide your real address or if you want to tell your address everyone but do not want to craft expensive Advanced Crystal Interface block.

### Changed
- SGS tries to utilize all available modems except ender modem now.
- SGS will use all available speaker peripherals for alarm.
- Pressed buttons in PSG > Dial window are colored orange now.
- All input fields in dialog windows will have white background now.
- Pending keys now makred with `*`. Previously they were marked only with yellow color, but this was not visible if this key is selected.
- PSG will try to assign name for SGS key from addressbook using its local address for keyring.

### Fixed
- Long delays when pressed symbol appears in dialed address string in PSG > Dial window.
- You can not encode the same symbol twice in PSG > Dial window now.
- Dialing sequence freeze if the same symbol appears several times in address buffer on engage remote call.
- Reduced the amout of synchronization events. Previously it was possible to overflow the event queues in PSG instances if game server throttles.
- Timeouts due event queue overflow.
- Pending key were not removed from key list on deny.

### Removed
- The ability to reset a stargate by pressing PoO button in PSG > Dial window. There is literally "Reset" button next to it!

## v1.1.2 2024-01-01

### Fixed
- Program crash on attempt to authorize introduced by previous release.

## v1.1.1 2024-12-31

### Fixed
- Annoing message pop up "No iris response!" even when there is no stargate nearby.
- Some dialog windows will be shown in turn. That is, not at the same time. For example, if you receive 3 text messages at the same time, you will see them all in order you received them, one by one.

## v1.1.0 2024-12-13

### Added
- Support for stargates that are very close to each other. In this case Pocket Stargate prefers the nearest stargate (determines by distance to wireless modem).

### Changed
- Fast dialing mode now faster. All chevrons are encoded in one tick.
- Greatly redused the amount of coroutines in the all distributions.
- Now crash report uses simulated file system file names in stacktrace.

### Fixed
- #3 PSG installer did not save the addresses.conf location parameter.
- Incomlete connected address were sent from a stargate server when some "engaged chevron" events were missed by the stargate server.

## v1.0.0 2024-11-26

This version is incompatible with Stargate Journey version 0.6.32 and below.

### Added
- New program "Security Terminal" (SSG).
- Authorization keys. Now you can open an iris on the other side by presenting your identity via a private key.
- Private key password encryption.
- Crash report generation.
- Audit journal (SSG).
- Stargate filter configurer (SSG).
- Iris control (SSG).

### Changed
- Installation system requires to download only a single file now: the installer itself.
- Dialed address will be shown even if a basic stargate interface is used on the server.

### Deleted
- You can't change stargate network ID in PSG now. (mooved to SSG)
- You can't control network restriction setting in PSG now. (mooved to SSG)
- You can't update energy target in PSG now. (mooved to SSG)

### Fixed
- A lot of synchronization issues and some loss of events.
- Script compillation failure due old Lua version. Pocket stargate is working on Minecraft 1.19 now.

## v0.2.0 2024-09-25

### Added
- Added scroll buttons for addressbook (necessary for scrolling on a monitor).
- Security alarm apon incomming wormhole (you need to attach a speaker for this feature).

### Changed
- The server and the client will prefer but not require a wireless modem (thats it, they can use wired modem now).
- You can now enforce manual dialing for Milky Way stargate even if a crystal interface is being used.

### Fixed
- Fixed typo in addresses.conf file for *Cavum Tenebrae* world.
- UI become more adaptive for selected monitor.
- Fixed optimal rotation direction for Milky Way stargate manual dialing.
