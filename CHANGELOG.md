# Changelog

All notable changes to this project will be documented in this file.

## [0.2.9] - 2026-02-28

### Fixed
- **Win32API dependency** - Added missing `win32api` gem requirement and `require 'win32api'` statement for Windows terminal support

## [0.2.8] - 2026-02-28

### Fixed
- **Windows navigation support** - Fixed keyboard navigation not working on Windows by implementing Windows Console API support
- Added cross-platform terminal setup/cleanup (`setup_terminal`/`cleanup_terminal`)
- Implemented Windows-specific `read_char` method for proper key input handling
- Console mode is now properly saved and restored on Windows platforms

## [0.2.7] - 2026-02-28

### Fixed
- **Auto-create profiles.json** - App now automatically creates the config directory and empty profiles.json file on first run instead of exiting with an error

## [0.2.6] - 2026-02-27

### Added
- **Download progress bar** - Visual progress indicator when downloading files with percentage, file size, and completion status
- **Loading indicators** - Show "Loading buckets..." and "Loading directory contents..." when fetching data from S3

### Fixed
- **Ruby compatibility** - Fixed `Data.define` error for Ruby versions < 3.2 by using `Struct` instead

## [0.1.1] - 2026-02-27

### Added
- **Scrollable file lists** - Large file lists are now scrollable with proper pagination
- **Node count indicator** - Display current node / total nodes in bottom right corner of footer
- **Relative time formatting** - Show "Xs/Xm/Xh/Xd ago" for items modified within 2 weeks, with consistent alignment
- **Cursor navigation improvements** - Cursor stays at last visible position when navigating past end

### Changed
- Improved footer layout with keyboard shortcuts on left and node count on right
- Time formatting now uses relative time for recent items while maintaining alignment

## [0.1.0] - Previous Release

### Added
- Initial S3-compatible browser TUI
- Profile management (add, edit, delete profiles)
- Bucket browsing and navigation
- Object listing with file/folder distinction
- Search functionality across profiles, buckets, and objects
- File download capability
- Interactive keyboard navigation

[0.2.9]: https://github.com/adiprnm/betters3tui/compare/v0.2.8...v0.2.9
[0.2.8]: https://github.com/adiprnm/betters3tui/compare/v0.2.7...v0.2.8
[0.2.7]: https://github.com/adiprnm/betters3tui/compare/v0.2.6...v0.2.7
[0.2.6]: https://github.com/adiprnm/betters3tui/compare/v0.2.5...v0.2.6
[0.1.1]: https://github.com/adiprnm/betters3tui/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/adiprnm/betters3tui/releases/tag/v0.1.0
