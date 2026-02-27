# BetterS3TUI

A TUI (Terminal User Interface) S3-compatible browser.

## Features

- Browse S3-compatible storage from your terminal
- Interactive interface for easy navigation
- Support for multiple S3-compatible services
- **Sort files by Name, Size, or Date** (interactive menu)
- Search across profiles, buckets, and objects
- Download files
- Multiple profile support

## Installation

```bash
git clone https://github.com/adiprnm/betters3tui.git
cd betters3tui
bundle install
```

## Usage

```bash
ruby betters3tui.rb
```

### Navigation

- `↑/↓` or `j/k` - Navigate up/down
- `Enter` - Select/open item
- `Esc` or `Backspace` - Go back
- `/` - Search
- `q` - Quit

### Object List (File Browser)

- `s` - Open sort menu
- `d` - Download current file

### Sort Menu

- `↑/↓` - Navigate sort options
- `Space` - Select sort column (stays in menu)
- `Enter` - Select sort column and exit
- `r` - Reverse sort direction (asc/desc)
- `Esc` - Cancel

### Sort Indicator

The header shows the current sort with direction:
- `▲` - Ascending order
- `▼` - Descending order

## License

MIT
