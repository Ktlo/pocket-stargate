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
