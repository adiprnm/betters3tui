#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "aws-sdk-s3"
require_relative "lib/tui"
require_relative "lib/fuzzy"

PROFILES_PATH = File.expand_path("~/.config/betters3tui/profiles.json")
DOWNLOADS_PATH = File.expand_path("~/Downloads")

class S3Browser
  include Tui::Helpers

  def initialize
    @profiles = load_profiles
    @current_profile = nil
    @s3_client = nil
    @buckets = []
    @current_bucket = nil
    @objects = []
    @current_prefix = ""
    @selected_index = 0
    @scroll_offset = 0
    @mode = :profile_select  # :profile_select, :bucket_select, :object_list
    @message = nil
    @message_time = nil
    
    # Search state
    @search_mode = false
    @search_query = String.new
    @search_results = []
    @search_cursor = 0
  end

  def run
    if @profiles.empty?
      puts "No profiles found at #{PROFILES_PATH}"
      puts "Please create a profiles.json file with your S3 credentials."
      exit 1
    end

    setup_terminal
    
    loop do
      render
      handle_input
    end
  rescue Interrupt
    cleanup_terminal
    puts "\nGoodbye!"
  ensure
    cleanup_terminal
  end

  private

  def load_profiles
    return [] unless File.exist?(PROFILES_PATH)
    JSON.parse(File.read(PROFILES_PATH))
  rescue JSON::ParserError
    []
  end

  def setup_terminal
    @original_stty = `stty -g 2>/dev/null`.chomp
    system("stty -echo -icanon raw 2>/dev/null")
    print Tui::ANSI::ALT_SCREEN_ON
    print Tui::ANSI::HIDE
    $stdout.flush
  end

  def cleanup_terminal
    print Tui::ANSI::ALT_SCREEN_OFF
    print Tui::ANSI::SHOW
    print Tui::ANSI::RESET
    system("stty #{@original_stty} 2>/dev/null") unless @original_stty.empty?
    $stdout.flush
  end

  def render
    screen = Tui::Screen.new
    
    # Header
    screen.header.add_line do |line|
      line.write << bold("📁 BetterS3TUI")
      line.right.write_dim("Profile: #{@current_profile ? @current_profile['name'] : 'None'}")
    end
    
    if @current_profile && @current_bucket
      screen.header.add_line do |line|
        line.write.write_dim("Bucket: ") << @current_bucket
        line.right.write_dim("Prefix: #{@current_prefix.empty? ? '/' : @current_prefix}")
      end
    end
    
    # Search input line when in search mode
    if @search_mode
      screen.header.add_line do |line|
        line.write.write_highlight("Search: ")
        search_field = Tui::InputField.new(placeholder: "", text: @search_query, cursor: @search_cursor)
        line.write << search_field.to_s
        line.mark_has_input("Search: ".length)
      end
    end
    
    screen.header.divider
    
    # Body content based on mode
    if @search_mode && @search_results.any?
      render_search_results(screen)
    else
      case @mode
      when :profile_select
        render_profile_list(screen)
      when :bucket_select
        render_bucket_list(screen)
      when :object_list
        render_object_list(screen)
      end
    end
    
    # Footer
    screen.footer.divider
    screen.footer.add_line do |line|
      line.write.write_dim(footer_text)
    end
    
    if @message && Time.now - @message_time < 3
      screen.footer.add_line do |line|
        line.write << (@message.include?("Error") ? Tui::Text.accent(@message) : Tui::Text.highlight(@message))
      end
    end
    
    screen.flush
  end

  def render_search_results(screen)
    @search_results.each_with_index do |result, idx|
      screen.body.add_line(
        background: idx == @selected_index ? Tui::Palette::SELECTED_BG : nil
      ) do |line|
        prefix = idx == @selected_index ? "→ " : "  "
        entry = result[:entry]
        positions = result[:positions]
        text = result[:text]
        
        # Highlight matching characters
        highlighted = highlight_matches(text, positions)
        
        if entry[:type] == :directory
          line.write << prefix << emoji("📂") << " " << highlighted
        else
          line.write << prefix << emoji("📄") << " " << highlighted
          line.right.write_dim(format_size(entry[:size])) << "  " << format_time(entry[:last_modified])
        end
      end
    end
  end

  def highlight_matches(text, positions)
    return text if positions.nil? || positions.empty?
    
    result = String.new
    text.chars.each_with_index do |char, idx|
      if positions.include?(idx)
        result << Tui::Text.highlight(char)
      else
        result << char
      end
    end
    result
  end

  def render_profile_list(screen)
    @profiles.each_with_index do |profile, idx|
      screen.body.add_line(
        background: idx == @selected_index ? Tui::Palette::SELECTED_BG : nil
      ) do |line|
        prefix = idx == @selected_index ? "→ " : "  "
        line.write << prefix << profile['name']
        line.right.write_dim(profile['endpoint'])
      end
    end
  end

  def render_bucket_list(screen)
    @buckets.each_with_index do |bucket, idx|
      screen.body.add_line(
        background: idx == @selected_index ? Tui::Palette::SELECTED_BG : nil
      ) do |line|
        prefix = idx == @selected_index ? "→ " : "  "
        line.write << prefix << emoji("📁") << " " << bucket.name
      end
    end
  end

  def render_object_list(screen)
    # Add ".." for navigation up
    if !@current_prefix.empty? || @objects.any? { |obj| obj.key.include?("/") }
      screen.body.add_line(
        background: @selected_index == 0 ? Tui::Palette::SELECTED_BG : nil
      ) do |line|
        prefix = @selected_index == 0 ? "→ " : "  "
        line.write << prefix << emoji("📂") << " .."
      end
    end
    
    start_idx = @current_prefix.empty? && !@objects.any? { |obj| obj.key.include?("/") } ? 0 : 1
    
    @objects.each_with_index do |obj, idx|
      actual_idx = idx + start_idx
      is_selected = actual_idx == @selected_index
      
      screen.body.add_line(
        background: is_selected ? Tui::Palette::SELECTED_BG : nil
      ) do |line|
        prefix = is_selected ? "→ " : "  "
        
        if obj.key.end_with?("/")
          line.write << prefix << emoji("📂") << " " << File.basename(obj.key)
        else
          line.write << prefix << emoji("📄") << " " << File.basename(obj.key)
          line.right.write_dim(format_size(obj.size)) << "  " << format_time(obj.last_modified)
        end
      end
    end
  end

  def footer_text
    if @search_mode
      "↑↓ navigate  Enter select  Esc/Ctrl-c exit search"
    else
      case @mode
      when :profile_select
        "↑↓/jk navigate  / search  Enter select  q quit"
      when :bucket_select
        "↑↓/jk navigate  / search  Enter open  Esc/⌫ back  q quit"
      when :object_list
        "↑↓/jk navigate  / search  Enter open/download  Esc/⌫ back  d download  q quit"
      end
    end
  end

  def handle_input
    char = $stdin.getc
    return unless char
    
    if @search_mode
      handle_search_input(char)
    else
      handle_normal_input(char)
    end
  end

  def handle_search_input(char)
    case char
    when "\e"
      # Exit search mode
      @search_mode = false
      @search_query = String.new
      @search_results = []
      @selected_index = 0
    when "\r", "\n"  # Enter
      select_search_result
    when "\x7F"  # Backspace
      if @search_query.length > 0
        @search_query = @search_query[0...-1]
        @search_cursor = @search_query.length
        perform_search
      end
    when "\x03"  # Ctrl-C
      @search_mode = false
      @search_query = String.new
      @search_results = []
      @selected_index = 0
    when "\e[A"  # Up arrow (from raw mode)
      move_selection(-1)
    when "\e[B"  # Down arrow (from raw mode)
      move_selection(1)
    when /[[:print:]]/
      @search_query << char
      @search_cursor = @search_query.length
      perform_search
    end
  end

  def handle_normal_input(char)
    case char
    when "\e"
      # Escape sequence - wait a tiny bit for sequence characters
      seq = nil
      begin
        # Wait up to 50ms for escape sequence
        if IO.select([$stdin], nil, nil, 0.05)
          seq = $stdin.read_nonblock(2, exception: false)
        end
      rescue
        # Ignore errors
      end
      
      if seq
        case seq
        when "[A"  # Up arrow
          move_selection(-1)
        when "[B"  # Down arrow
          move_selection(1)
        end
      else
        # Just Escape key
        go_back
      end
    when "\r", "\n"  # Enter
      select_current
    when "j"
      move_selection(1)
    when "k"
      move_selection(-1)
    when "/"
      enter_search_mode
    when "\x7F"  # Backspace
      go_back
    when "d", "D"
      download_current if @mode == :object_list
    when "q", "Q"
      raise Interrupt
    end
  end

  def enter_search_mode
    @search_mode = true
    @search_query = String.new
    @search_cursor = 0
    @search_results = []
    @selected_index = 0
    
    # Pre-populate searchable items based on current mode
    case @mode
    when :profile_select
      @searchable_items = @profiles.map.with_index do |p, idx|
        { text: p['name'], data: { type: :profile, index: idx, profile: p } }
      end
    when :bucket_select
      @searchable_items = @buckets.map.with_index do |b, idx|
        { text: b.name, data: { type: :bucket, index: idx, bucket: b } }
      end
    when :object_list
      @searchable_items = @objects.map.with_index do |obj, idx|
        is_dir = obj.key.end_with?("/")
        text = is_dir ? File.basename(obj.key) : File.basename(obj.key)
        { 
          text: text, 
          data: { 
            type: is_dir ? :directory : :file, 
            index: idx, 
            obj: obj,
            size: obj.size,
            last_modified: obj.last_modified
          } 
        }
      end
    end
  end

  def perform_search
    if @search_query.empty?
      @search_results = []
      @selected_index = 0
      return
    end
    
    fuzzy = Fuzzy.new(@searchable_items)
    @search_results = []
    
    fuzzy.match(@search_query).each do |entry, positions, score|
      @search_results << {
        entry: entry[:data],
        positions: positions,
        text: entry[:text],
        score: score
      }
    end
    
    @selected_index = 0
  end

  def select_search_result
    return unless @search_results[@selected_index]
    
    result = @search_results[@selected_index]
    data = result[:entry]
    
    case data[:type]
    when :profile
      @search_mode = false
      @search_query = String.new
      @search_results = []
      @current_profile = data[:profile]
      @selected_index = 0
      connect_to_s3
      @mode = :bucket_select
      list_buckets
    when :bucket
      @search_mode = false
      @search_query = String.new
      @search_results = []
      @current_bucket = data[:bucket].name
      @selected_index = 0
      @current_prefix = ""
      @mode = :object_list
      list_objects
    when :directory
      @search_mode = false
      @search_query = String.new
      @search_results = []
      obj = data[:obj]
      @current_prefix = obj.key
      list_objects
      @selected_index = 0
    when :file
      @search_mode = false
      @search_query = String.new
      @search_results = []
      obj = data[:obj]
      download_file(obj.key)
    end
  end

  def move_selection(delta)
    max = if @search_mode && @search_results.any?
      @search_results.length - 1
    else
      case @mode
      when :profile_select
        @profiles.length - 1
      when :bucket_select
        @buckets.length - 1
      when :object_list
        max = @objects.length
        max += 1 if !@current_prefix.empty? || @objects.any? { |obj| obj.key.include?("/") }
        max
      end
    end
    
    @selected_index = [[@selected_index + delta, 0].max, max].min
  end

  def select_current
    case @mode
    when :profile_select
      @current_profile = @profiles[@selected_index]
      @selected_index = 0
      connect_to_s3
      @mode = :bucket_select
      list_buckets
    when :bucket_select
      @current_bucket = @buckets[@selected_index].name
      @selected_index = 0
      @current_prefix = ""
      @mode = :object_list
      list_objects
    when :object_list
      handle_object_select
    end
  end

  def handle_object_select
    start_idx = @current_prefix.empty? && !@objects.any? { |obj| obj.key.include?("/") } ? 0 : 1
    
    if @selected_index == 0 && start_idx == 1
      # Navigate up
      if @current_prefix.empty?
        @mode = :bucket_select
        @current_bucket = nil
        @selected_index = 0
      else
        parts = @current_prefix.split("/").reject(&:empty?)
        parts.pop
        @current_prefix = parts.empty? ? "" : parts.join("/") + "/"
        list_objects
        @selected_index = 0
      end
      return
    end
    
    obj_idx = @selected_index - start_idx
    obj = @objects[obj_idx]
    return unless obj
    
    if obj.key.end_with?("/")
      @current_prefix = obj.key
      list_objects
      @selected_index = 0
    else
      download_file(obj.key)
    end
  end

  def go_back
    if @search_mode
      @search_mode = false
      @search_query = String.new
      @search_results = []
      @selected_index = 0
      return
    end
    
    case @mode
    when :bucket_select
      @current_profile = nil
      @s3_client = nil
      @mode = :profile_select
      @selected_index = 0
    when :object_list
      if @current_prefix.empty?
        @current_bucket = nil
        @mode = :bucket_select
        @selected_index = 0
      else
        parts = @current_prefix.split("/").reject(&:empty?)
        parts.pop
        @current_prefix = parts.empty? ? "" : parts.join("/") + "/"
        list_objects
        @selected_index = 0
      end
    end
  end

  def connect_to_s3
    credentials = Aws::Credentials.new(
      @current_profile['access_key'],
      @current_profile['secret_key']
    )
    
    client_options = {
      credentials: credentials,
      region: @current_profile['region'] || 'us-east-1'
    }
    
    if @current_profile['endpoint']
      client_options[:endpoint] = @current_profile['endpoint']
      client_options[:force_path_style] = true unless @current_profile['is_aws']
    end
    
    @s3_client = Aws::S3::Client.new(client_options)
  rescue => e
    show_message("Error connecting: #{e.message}")
  end

  def list_buckets
    return unless @s3_client
    
    response = @s3_client.list_buckets
    @buckets = response.buckets
  rescue => e
    show_message("Error listing buckets: #{e.message}")
    @buckets = []
  end

  def list_objects
    return unless @s3_client && @current_bucket
    
    delimiter = "/"
    response = @s3_client.list_objects_v2(
      bucket: @current_bucket,
      prefix: @current_prefix,
      delimiter: delimiter
    )
    
    @objects = []
    
    # Add common prefixes (directories)
    response.common_prefixes&.each do |prefix|
      @objects << OpenStruct.new(
        key: prefix.prefix,
        size: 0,
        last_modified: nil
      )
    end
    
    # Add actual objects
    response.contents&.each do |obj|
      next if obj.key == @current_prefix  # Skip the prefix itself
      @objects << obj
    end
    
    # Sort: directories first, then by name
    @objects.sort_by! do |obj|
      [obj.key.end_with?("/") ? 0 : 1, obj.key.downcase]
    end
  rescue => e
    show_message("Error listing objects: #{e.message}")
    @objects = []
  end

  def download_current
    start_idx = @current_prefix.empty? && !@objects.any? { |obj| obj.key.include?("/") } ? 0 : 1
    
    return if @selected_index == 0 && start_idx == 1
    
    obj_idx = @selected_index - start_idx
    obj = @objects[obj_idx]
    return unless obj
    return if obj.key.end_with?("/")
    
    download_file(obj.key)
  end

  def download_file(key)
    return unless @s3_client && @current_bucket
    
    filename = File.basename(key)
    download_path = File.join(DOWNLOADS_PATH, filename)
    
    # Handle duplicates
    counter = 1
    original_path = download_path
    while File.exist?(download_path)
      ext = File.extname(original_path)
      base = File.basename(original_path, ext)
      download_path = File.join(DOWNLOADS_PATH, "#{base}_#{counter}#{ext}")
      counter += 1
    end
    
    begin
      @s3_client.get_object(
        response_target: download_path,
        bucket: @current_bucket,
        key: key
      )
      show_message("Downloaded: #{filename}")
    rescue => e
      show_message("Error downloading: #{e.message}")
    end
  end

  def show_message(msg)
    @message = msg
    @message_time = Time.now
  end

  def format_size(bytes)
    return "-" if bytes.nil? || bytes == 0
    
    units = ["B", "KB", "MB", "GB", "TB"]
    idx = 0
    size = bytes.to_f
    
    while size >= 1024 && idx < units.length - 1
      size /= 1024
      idx += 1
    end
    
    if idx == 0
      "#{size.to_i} #{units[idx]}"
    else
      "%.2f #{units[idx]}" % size
    end
  end

  def format_time(time)
    return "-" if time.nil?
    time.strftime("%Y-%m-%d %H:%M")
  end
end

# Main entry point
if __FILE__ == $0
  browser = S3Browser.new
  browser.run
end
