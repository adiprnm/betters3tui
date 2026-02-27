# Changelog

All notable changes to this project will be documented in this file.

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

[0.1.1]: https://github.com/adiprnm/betters3tui/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/adiprnm/betters3tui/releases/tag/v0.1.0
