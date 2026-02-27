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

### Option 1: Direct Installation

```bash
git clone https://github.com/adiprnm/betters3tui.git
cd betters3tui
bundle install
ruby betters3tui.rb
```

### Option 2: Docker (Recommended)

Build and run using Docker Compose:

```bash
# Clone the repository
git clone https://github.com/adiprnm/betters3tui.git
cd betters3tui

# Build the Docker image
docker-compose build

# Run the application
docker-compose run betters3tui
```

Or using Docker directly:

```bash
# Build the image
docker build -t betters3tui .

# Run with volume mounts for config and downloads
docker run -it \
  -v ~/.config/betters3tui:/root/.config/betters3tui \
  -v ~/Downloads:/root/Downloads \
  betters3tui
```

## Configuration

Before running, create a profiles configuration file at `~/.config/betters3tui/profiles.json`:

```json
[
  {
    "name": "my-s3",
    "endpoint": "https://s3.example.com",
    "access_key": "your-access-key",
    "secret_key": "your-secret-key",
    "region": "us-east-1",
    "is_aws": false
  }
]
```

## Usage

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

## Development

### Running Tests

```bash
bundle exec rake test
```

## License

MIT
