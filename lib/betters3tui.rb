#!/usr/bin/env ruby
# frozen_string_literal: true

VERSION = "0.2.7"

require "json"
require "aws-sdk-s3"
require_relative "tui"
require_relative "fuzzy"

PROFILES_PATH = File.expand_path("~/.config/betters3tui/profiles.json")
DOWNLOADS_PATH = File.expand_path("~/Downloads")

class S3Browser
  include Tui::Helpers

  NODE_HEIGHT = 4

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
    @mode = :profile_select  # :profile_select, :bucket_select, :object_list, :add_profile, :edit_profile, :sort_menu

    # Profile creation/edit state
    @new_profile = {}
    @profile_fields = [
      { key: 'name', label: 'Profile Name', required: true },
      { key: 'endpoint', label: 'Endpoint URL', required: false },
      { key: 'access_key', label: 'Access Key', required: true },
      { key: 'secret_key', label: 'Secret Key', required: true, secret: true },
      { key: 'region', label: 'Region', required: false },
      { key: 'is_aws', label: 'Is AWS? (y/n)', required: false, boolean: true }
    ]
    @current_field_index = 0
    @editing_profile_index = nil

    # Delete confirmation state
    @delete_confirm_mode = false
    @delete_profile_name = nil

    # Search state
    @search_mode = false
    @search_query = String.new
    @search_results = []
    @search_cursor = 0

    # Sort state
    @sort_by = :name
    @sort_direction = :asc

    # Sort menu state
    @sort_menu_options = [
      { key: 'n', label: 'Name', value: :name },
      { key: 's', label: 'Size', value: :size },
      { key: 'd', label: 'Date', value: :date }
    ]
    @sort_menu_index = 0

    # Loading state
    @loading = false
    @loading_message = ""
  end

  def run
    ensure_profiles_file_exists
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

  def ensure_profiles_file_exists
    require 'fileutils'
    config_dir = File.dirname(PROFILES_PATH)
    FileUtils.mkdir_p(config_dir) unless File.exist?(config_dir)

    unless File.exist?(PROFILES_PATH)
      File.write(PROFILES_PATH, JSON.pretty_generate([]))
    end
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
    system("stty #{@original_stty} 2>/dev/null") if @original_stty && !@original_stty.empty?
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

    # Show sort indicator when in object list mode
    if @mode == :object_list || @mode == :sort_menu
      screen.header.add_line do |line|
        dir_indicator = @sort_direction == :asc ? "▲" : "▼"
        line.right.write_dim("Sort: #{@sort_by} #{dir_indicator}")
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
      when :add_profile
        render_add_profile(screen)
      when :edit_profile
        render_edit_profile(screen)
      when :bucket_select
        render_bucket_list(screen)
      when :object_list
        render_object_list(screen)
      when :sort_menu
        render_sort_menu(screen)
      end
    end

    # Footer
    screen.footer.divider
    screen.footer.add_line do |line|
      line.write.write_dim(footer_text)
      line.right.write_dim(node_count_text)
    end

    if @loading
      screen.footer.add_line do |line|
        line.write << Tui::Text.highlight(@loading_message)
      end
    elsif @downloading && @download_progress
      progress = @download_progress
      percent = (progress[:downloaded].to_f / progress[:total] * 100).round(1)
      bar_width = 20
      filled = (percent / 100 * bar_width).to_i
      bar = "█" * filled + "░" * (bar_width - filled)
      downloaded_str = format_size(progress[:downloaded])
      total_str = format_size(progress[:total])
      progress_msg = "Downloading #{progress[:filename]}: [#{bar}] #{percent}% (#{downloaded_str}/#{total_str})"
      screen.footer.add_line do |line|
        line.write << Tui::Text.highlight(progress_msg)
      end
    elsif @message && Time.now - @message_time < 3
      screen.footer.add_line do |line|
        line.write << (@message.include?("Error") ? Tui::Text.accent(@message) : Tui::Text.highlight(@message))
      end
    end

    screen.flush
  end

  def render_search_results(screen)
    max_nodes = calculate_max_nodes

    @search_results.each_with_index do |result, idx|
      next if idx < @scroll_offset
      next if idx >= @scroll_offset + max_nodes

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
    max_nodes = calculate_max_nodes

    @profiles.each_with_index do |profile, idx|
      next if idx < @scroll_offset
      next if idx >= @scroll_offset + max_nodes

      is_selected = idx == @selected_index
      screen.body.add_line(
        background: is_selected ? Tui::Palette::SELECTED_BG : nil
      ) do |line|
        prefix = is_selected ? "→ " : "  "
        line.write << prefix << profile['name']
        if is_selected
          line.right.write(Tui::Text.highlight(" e ") + "edit  " + Tui::Text.accent(" d ") + "delete  " + profile['endpoint'].to_s)
        else
          line.right.write_dim(profile['endpoint'])
        end
      end
    end

    # Add "+ Add new profile" option
    add_idx = @profiles.length
    if add_idx >= @scroll_offset && add_idx < @scroll_offset + max_nodes
      screen.body.add_line(
        background: add_idx == @selected_index ? Tui::Palette::SELECTED_BG : nil
      ) do |line|
        prefix = add_idx == @selected_index ? "→ " : "  "
        line.write << prefix << "+ Add new profile"
      end
    end
  end

  def render_edit_profile(screen)
    screen.body.add_line do |line|
      line.write.write_highlight("Edit Profile")
    end
    screen.body.add_line

    @profile_fields.each_with_index do |field, idx|
      is_current = idx == @current_field_index
      value = @new_profile[field[:key]] || ""

      # Mask secret fields
      display_value = if field[:secret] && !value.empty?
        "*" * value.length
      elsif field[:boolean]
        value == true || value.to_s.downcase == 'y' ? "yes" : (value == false || value.to_s.downcase == 'n' ? "no" : "")
      else
        value
      end

      screen.body.add_line(
        background: is_current ? Tui::Palette::SELECTED_BG : nil
      ) do |line|
        prefix = is_current ? "→ " : "  "
        label = "#{field[:label]}:"
        if field[:required]
          label = "#{field[:label]}* :"
        end

        line.write << prefix << label

        if is_current
          # Show cursor for current field
          cursor_char = display_value.empty? ? "_" : display_value[-1]
          visible_text = display_value.empty? ? "" : display_value[0..-2]
          line.write << " " << visible_text << Tui::Text.highlight(cursor_char)
        else
          line.write << " " << display_value
        end
      end
    end

    screen.body.add_line
    screen.body.add_line do |line|
      line.write.write_dim("* required field")
    end
    screen.body.add_line do |line|
      line.write.write_dim("Tab/↓ next field  ↑ prev field  Enter save  Esc cancel")
    end
  end

  def render_add_profile(screen)
    screen.body.add_line do |line|
      line.write.write_highlight("Create New Profile")
    end
    screen.body.add_line

    @profile_fields.each_with_index do |field, idx|
      is_current = idx == @current_field_index
      value = @new_profile[field[:key]] || ""

      # Mask secret fields
      display_value = if field[:secret] && !value.empty?
        "*" * value.length
      elsif field[:boolean]
        value == "y" || value == "Y" ? "yes" : (value == "n" || value == "N" ? "no" : "")
      else
        value
      end

      screen.body.add_line(
        background: is_current ? Tui::Palette::SELECTED_BG : nil
      ) do |line|
        prefix = is_current ? "→ " : "  "
        label = "#{field[:label]}:"
        if field[:required]
          label = "#{field[:label]}* :"
        end

        line.write << prefix << label

        if is_current
          # Show cursor for current field
          cursor_char = display_value.empty? ? "_" : display_value[-1]
          visible_text = display_value.empty? ? "" : display_value[0..-2]
          line.write << " " << visible_text << Tui::Text.highlight(cursor_char)
        else
          line.write << " " << display_value
        end
      end
    end

    screen.body.add_line
    screen.body.add_line do |line|
      line.write.write_dim("* required field")
    end
    screen.body.add_line do |line|
      line.write.write_dim("Tab/↓ next field  ↑ prev field  Enter save  Esc cancel")
    end
  end

  def render_bucket_list(screen)
    max_nodes = calculate_max_nodes

    @buckets.each_with_index do |bucket, idx|
      next if idx < @scroll_offset
      next if idx >= @scroll_offset + max_nodes

      screen.body.add_line(
        background: idx == @selected_index ? Tui::Palette::SELECTED_BG : nil
      ) do |line|
        prefix = idx == @selected_index ? "→ " : "  "
        line.write << prefix << emoji("📁") << " " << bucket.name
      end
    end
  end

  def render_object_list(screen)
    max_nodes = calculate_max_nodes

    # Calculate total items and start index
    has_parent = !@current_prefix.empty? || @objects.any? { |obj| obj.key.include?("/") }
    start_idx = has_parent ? 1 : 0

    # Add ".." for navigation up (only visible when not scrolled)
    if has_parent && @scroll_offset == 0
      screen.body.add_line(
        background: @selected_index == 0 ? Tui::Palette::SELECTED_BG : nil
      ) do |line|
        prefix = @selected_index == 0 ? "→ " : "  "
        line.write << prefix << emoji("📂") << " .."
      end
    end

    @objects.each_with_index do |obj, idx|
      actual_idx = idx + start_idx
      next if actual_idx < @scroll_offset
      next if actual_idx >= @scroll_offset + max_nodes

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

  def render_sort_menu(screen)
    screen.body.add_line do |line|
      line.write.write_highlight("Sort by:")
    end
    screen.body.add_line

    @sort_menu_options.each_with_index do |option, idx|
      is_current = idx == @selected_index
      is_selected = @sort_by == option[:value]

      screen.body.add_line(
        background: is_current ? Tui::Palette::SELECTED_BG : nil
      ) do |line|
        prefix = is_current ? "→ " : "  "
        indicator = is_selected ? " ● " : " ○ "
        dir_indicator = is_selected ? (@sort_direction == :asc ? "↑" : "↓") : ""

        line.write << prefix << indicator << option[:label]
        line.right.write_dim(dir_indicator) if is_selected
      end
    end

    screen.body.add_line
    screen.body.add_line do |line|
      line.write.write_dim("↑↓ navigate  Enter select  r reverse  Esc cancel")
    end
  end

  def footer_text
    if @search_mode
      "↑↓ navigate  Enter select  Esc/Ctrl-c exit search"
    else
      case @mode
      when :profile_select
        "↑↓/jk navigate  a add  e edit  d delete  / search  Enter select  q quit"
      when :add_profile
        "Tab/↓ next  ↑ prev  Enter save  Esc cancel"
      when :edit_profile
        "Tab/↓ next  ↑ prev  Enter save  Esc cancel"
      when :bucket_select
        "↑↓/jk navigate  / search  Enter open  Esc/⌫ back  q quit"
      when :object_list
        "↑↓/jk navigate  / search  s sort  Enter open/download  Esc/⌫ back  d download  q quit"
      when :sort_menu
        "↑↓ navigate  Enter select  r reverse  Esc cancel"
      end
    end
  end

  def node_count_text
    # Get current item count based on mode
    total_items = case @mode
    when :profile_select
      @profiles.length + 1  # +1 for "Add new profile"
    when :bucket_select
      @buckets.length
    when :object_list
      has_parent = !@current_prefix.empty? || @objects.any? { |obj| obj.key.include?("/") }
      @objects.length + (has_parent ? 1 : 0)  # +1 for ".."
    when :sort_menu
      @sort_menu_options.length
    else
      0
    end
    
    # Current node is selected_index + 1 (1-based)
    current_node = @selected_index + 1
    
    total_items > 0 ? "#{current_node}/#{total_items}" : "0/0"
  end

  def handle_input
    char = $stdin.getc
    return unless char

    if @delete_confirm_mode
      handle_delete_confirmation(char)
      return
    end

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
      @scroll_offset = 0
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
      @scroll_offset = 0
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
          if @mode == :add_profile || @mode == :edit_profile
            move_field(-1)
          else
            move_selection(-1)
          end
        when "[B"  # Down arrow
          if @mode == :add_profile || @mode == :edit_profile
            move_field(1)
          else
            move_selection(1)
          end
        end
      else
        # Just Escape key
        if @mode == :add_profile || @mode == :edit_profile
          cancel_profile_form
        else
          go_back
        end
      end
    when "\r", "\n"  # Enter
      if @mode == :add_profile
        save_profile
      elsif @mode == :edit_profile
        update_profile
      else
        select_current
      end
    when "j"
      if @mode != :add_profile && @mode != :edit_profile
        move_selection(1)
      else
        handle_profile_input(char)
      end
    when "k"
      if @mode != :add_profile && @mode != :edit_profile
        move_selection(-1)
      else
        handle_profile_input(char)
      end
    when "a", "A"
      if @mode == :profile_select
        start_add_profile
      elsif @mode == :add_profile || @mode == :edit_profile
        handle_profile_input(char)
      end
    when "e", "E"
      if @mode == :profile_select && @selected_index < @profiles.length
        start_edit_profile
      elsif @mode == :add_profile || @mode == :edit_profile
        handle_profile_input(char)
      end
    when "d", "D"
      if @mode == :profile_select && @selected_index < @profiles.length
        delete_profile
      elsif @mode == :object_list
        download_current
      elsif @mode == :add_profile || @mode == :edit_profile
        handle_profile_input(char)
      end
    when "\t"  # Tab
      move_field(1) if @mode == :add_profile || @mode == :edit_profile
    when "/"
      if @mode == :add_profile || @mode == :edit_profile
        handle_profile_input(char)
      else
        enter_search_mode
      end
    when "\x7F"  # Backspace
      if @mode == :add_profile || @mode == :edit_profile
        handle_profile_backspace
      else
        go_back
      end
    when "q", "Q"
      if @mode == :add_profile || @mode == :edit_profile
        handle_profile_input(char)
      else
        raise Interrupt
      end
    when "s", "S"
      if @mode == :object_list
        enter_sort_menu
      elsif @mode == :add_profile || @mode == :edit_profile
        handle_profile_input(char)
      end
    when "r", "R"
      if @mode == :sort_menu
        @sort_direction = @sort_direction == :asc ? :desc : :asc
      elsif @mode == :add_profile || @mode == :edit_profile
        handle_profile_input(char)
      end
    when " "
      if @mode == :sort_menu
        # Select sort column without leaving menu
        selected_option = @sort_menu_options[@selected_index]
        @sort_by = selected_option[:value]
        sort_objects!
        show_message("Sorted by: #{@sort_by} (#{@sort_direction})")
      end
    else
      if (@mode == :add_profile || @mode == :edit_profile) && char =~ /[[:print:]]/
        handle_profile_input(char)
      end
    end
  end

  def start_add_profile
    @mode = :add_profile
    @new_profile = {}
    @current_field_index = 0
    @selected_index = 0
  end

  def cancel_profile_form
    @mode = :profile_select
    @new_profile = {}
    @scroll_offset = 0
    @current_field_index = 0
    @editing_profile_index = nil
  end

  def move_field(delta)
    max = @profile_fields.length - 1
    @current_field_index = [[@current_field_index + delta, 0].max, max].min
  end

  def handle_profile_input(char)
    field = @profile_fields[@current_field_index]
    key = field[:key]

    if field[:boolean]
      # Only allow y/n for boolean fields
      if char.downcase == 'y' || char.downcase == 'n'
        @new_profile[key] = char.downcase
      end
    else
      current = @new_profile[key] || ""
      @new_profile[key] = current + char
    end
  end

  def handle_profile_backspace
    field = @profile_fields[@current_field_index]
    key = field[:key]
    current = @new_profile[key] || ""
    if current.length > 0
      @new_profile[key] = current[0...-1]
    end
  end

  def save_profile
    # Validate required fields
    required_fields = @profile_fields.select { |f| f[:required] }
    missing = required_fields.select { |f| @new_profile[f[:key]].nil? || @new_profile[f[:key]].empty? }

    if missing.any?
      show_message("Error: #{missing.map { |f| f[:label] }.join(', ')} required")
      return
    end

    # Convert boolean field
    if @new_profile['is_aws']
      @new_profile['is_aws'] = @new_profile['is_aws'].downcase == 'y'
    end

    # Set default region if not provided
    @new_profile['region'] ||= 'us-east-1'

    # Save to file
    @profiles << @new_profile
    save_profiles_to_file

    @mode = :profile_select
    @new_profile = {}
    @current_field_index = 0
    @selected_index = @profiles.length - 1
    show_message("Profile created successfully!")
  end

  def start_edit_profile
    return if @selected_index >= @profiles.length

    @editing_profile_index = @selected_index
    @new_profile = @profiles[@selected_index].dup
    @mode = :edit_profile
    @current_field_index = 0
  end

  def update_profile
    return unless @editing_profile_index

    # Validate required fields
    required_fields = @profile_fields.select { |f| f[:required] }
    missing = required_fields.select { |f| @new_profile[f[:key]].nil? || @new_profile[f[:key]].empty? }

    if missing.any?
      show_message("Error: #{missing.map { |f| f[:label] }.join(', ')} required")
      return
    end

    # Convert boolean field
    if @new_profile['is_aws']
      @new_profile['is_aws'] = @new_profile['is_aws'].downcase == 'y'
    end

    # Set default region if not provided
    @new_profile['region'] ||= 'us-east-1'

    # Update profile
    @profiles[@editing_profile_index] = @new_profile
    save_profiles_to_file

    @mode = :profile_select
    @new_profile = {}
    @current_field_index = 0
    @editing_profile_index = nil
    @scroll_offset = 0
    show_message("Profile updated successfully!")
  end

  def delete_profile
    return if @selected_index >= @profiles.length

    @delete_confirm_mode = true
    @delete_profile_name = @profiles[@selected_index]['name']
    show_message("Delete profile '#{@delete_profile_name}'? Press 'y' to confirm, any key to cancel")
  end

  def handle_delete_confirmation(char)
    if char.downcase == 'y'
      # Actually delete
      @profiles.delete_at(@selected_index)
      save_profiles_to_file
      @selected_index = [@selected_index, @profiles.length - 1].min
      show_message("Profile '#{@delete_profile_name}' deleted!")
    else
      show_message("Delete cancelled")
    end
    @delete_confirm_mode = false
    @delete_profile_name = nil
  end

  def save_profiles_to_file
    require 'fileutils'
    config_dir = File.dirname(PROFILES_PATH)
    FileUtils.mkdir_p(config_dir) unless File.exist?(config_dir)

    File.write(PROFILES_PATH, JSON.pretty_generate(@profiles))
  end

  def enter_search_mode
    @search_mode = true
    @search_query = String.new
    @search_cursor = 0
    @search_results = []
    @selected_index = 0
    @scroll_offset = 0

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
    @scroll_offset = 0
  end

  def enter_sort_menu
    @mode = :sort_menu
    @selected_index = @sort_menu_options.index { |opt| opt[:value] == @sort_by } || 0
    @scroll_offset = 0
  end

  def select_sort_option
    selected_option = @sort_menu_options[@selected_index]
    @sort_by = selected_option[:value]
    sort_objects!
    @mode = :object_list
    @selected_index = 0
    @scroll_offset = 0
    show_message("Sorted by: #{@sort_by} (#{@sort_direction})")
  end

  def sort_objects!
    # Sort: directories always first, then by selected criteria
    @objects.sort_by! do |obj|
      is_dir = obj.key.end_with?("/")
      dir_key = is_dir ? 0 : 1

      sort_key = case @sort_by
      when :name
        obj.key.downcase
      when :size
        obj.size || 0
      when :date
        obj.last_modified || Time.at(0)
      end

      [dir_key, sort_key]
    end

    # Reverse if descending (but keep directories first)
    if @sort_direction == :desc
      # Separate directories and files
      dirs = @objects.select { |obj| obj.key.end_with?("/") }
      files = @objects.reject { |obj| obj.key.end_with?("/") }

      # Reverse only the files based on sort criteria
      files.reverse!

      @objects = dirs + files
    end
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
      @scroll_offset = 0
      connect_to_s3
      @mode = :bucket_select
      list_buckets
    when :bucket
      @search_mode = false
      @search_query = String.new
      @search_results = []
      @current_bucket = data[:bucket].name
      @selected_index = 0
      @scroll_offset = 0
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
      @scroll_offset = 0
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
        @profiles.length  # +1 for "Add new profile" option
      when :bucket_select
        @buckets.length - 1
      when :object_list
        max = @objects.length - 1
        max += 1 if !@current_prefix.empty? || @objects.any? { |obj| obj.key.include?("/") }
        max
      when :sort_menu
        @sort_menu_options.length - 1
      else
        return  # Don't move selection in other modes (add_profile, edit_profile)
      end
    end

    new_index = @selected_index + delta

    # Clamp to valid range
    if new_index < 0
      @selected_index = 0
      @scroll_offset = 0
    elsif new_index > max
      @selected_index = max
    else
      @selected_index = new_index
    end

    # Update scroll offset to keep selection visible
    update_scroll_for_selection
  end

  def update_scroll_for_selection
    max_nodes = calculate_max_nodes

    if @selected_index < @scroll_offset
      # Selection is above visible area
      @scroll_offset = @selected_index
    elsif @selected_index >= @scroll_offset + max_nodes
      # Selection is below visible area
      @scroll_offset = @selected_index - max_nodes + 1
    end

    # Clamp selected_index to stay within visible range
    # When cursor reaches max node, it stays at the last visible position
    @selected_index = [@selected_index, @scroll_offset + max_nodes - 1].min
  end

  def calculate_max_nodes
    # Get terminal height (rows)
    term_height, _ = Tui::Terminal.size

    # Ensure minimum terminal height
    min_terminal_height = 10
    term_height = [term_height, min_terminal_height].max

    # Count header lines that will be rendered
    header_lines = 1  # Title line
    header_lines += 1 if @current_profile && @current_bucket  # Bucket info
    header_lines += 1 if @mode == :object_list || @mode == :sort_menu  # Sort indicator
    header_lines += 1 if @search_mode  # Search input
    header_lines += 1  # Divider

    # Count footer lines that will be rendered
    footer_lines = 2  # Divider + footer text
    footer_lines += 1 if @message && Time.now - @message_time < 3

    # Calculate available lines for body content
    # Each item takes 1 line, so max_nodes = available lines
    available_lines = term_height - header_lines - footer_lines

    # Ensure at least some space for content (minimum 5 lines)
    [available_lines, 5].max
  end

  def select_current
    case @mode
    when :profile_select
      if @selected_index == @profiles.length
        # Selected "Add new profile"
        start_add_profile
        @scroll_offset = 0
      else
        @current_profile = @profiles[@selected_index]
        @selected_index = 0
        @scroll_offset = 0
        connect_to_s3
        @mode = :bucket_select
        list_buckets
      end
    when :bucket_select
      if @buckets[@selected_index].nil?
        @mode = :profile_select
        @current_profile = nil
        @s3_client = nil
        @selected_index = 0
        @scroll_offset = 0
        return
      end
      @current_bucket = @buckets[@selected_index].name
      @selected_index = 0
      @scroll_offset = 0
      @current_prefix = ""
      @mode = :object_list
      list_objects
    when :object_list
      handle_object_select
    when :sort_menu
      select_sort_option
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
        @scroll_offset = 0
      else
        parts = @current_prefix.split("/").reject(&:empty?)
        parts.pop
        @current_prefix = parts.empty? ? "" : parts.join("/") + "/"
        list_objects
        @selected_index = 0
        @scroll_offset = 0
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
      @scroll_offset = 0
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
      @scroll_offset = 0
    when :sort_menu
      @mode = :object_list
      @selected_index = 0
      @scroll_offset = 0
      return
    when :object_list
      if @current_prefix.empty?
        @current_bucket = nil
        @mode = :bucket_select
        @selected_index = 0
        @scroll_offset = 0
      else
        parts = @current_prefix.split("/").reject(&:empty?)
        parts.pop
        @current_prefix = parts.empty? ? "" : parts.join("/") + "/"
        list_objects
        @selected_index = 0
        @scroll_offset = 0
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

    @loading = true
    @loading_message = "Loading buckets..."
    render

    response = @s3_client.list_buckets
    @buckets = response.buckets
  rescue => e
    show_message("Error listing buckets: #{e.message}")
    @buckets = []
  ensure
    @loading = false
  end

  def list_objects
    return unless @s3_client && @current_bucket

    # Show loading indicator
    @loading = true
    @loading_message = "Loading directory contents..."
    render

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

    # Sort: directories first, then by selected criteria
    sort_objects!
  rescue => e
    show_message("Error listing objects: #{e.message}")
    @objects = []
  ensure
    @loading = false
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

    @downloading = true
    begin
      # Get file size first
      head_response = @s3_client.head_object(
        bucket: @current_bucket,
        key: key
      )
      total_size = head_response.content_length

      # Download with progress
      downloaded = 0
      File.open(download_path, 'wb') do |file|
        @s3_client.get_object(
          bucket: @current_bucket,
          key: key
        ) do |chunk|
          file.write(chunk)
          downloaded += chunk.bytesize
          @download_progress = {
            filename: filename,
            downloaded: downloaded,
            total: total_size
          }
          render
        end
      end
      show_message("Downloaded: #{filename}")
    rescue => e
      show_message("Error downloading: #{e.message}")
    ensure
      @downloading = false
      @download_progress = nil
    end
  end

  def show_download_progress(filename, downloaded, total)
    return if total.nil? || total == 0

    percent = (downloaded.to_f / total * 100).round(1)
    bar_width = 20
    filled = (percent / 100 * bar_width).to_i
    bar = "█" * filled + "░" * (bar_width - filled)

    downloaded_str = format_size(downloaded)
    total_str = format_size(total)

    @message = "Downloading #{filename}: [#{bar}] #{percent}% (#{downloaded_str}/#{total_str})"
    @message_time = Time.now
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
    
    now = Time.now
    diff = now - time
    
    # If more than 2 weeks ago, show formatted date
    if diff > 14 * 24 * 60 * 60  # 14 days in seconds
      return time.strftime("%Y-%m-%d %H:%M")
    end
    
    # Calculate relative time and pad to align with date format (16 chars)
    result = if diff < 60
      # Less than a minute
      "#{diff.to_i}s ago"
    elsif diff < 60 * 60
      # Less than an hour
      minutes = (diff / 60).to_i
      "#{minutes}m ago"
    elsif diff < 24 * 60 * 60
      # Less than a day
      hours = (diff / (60 * 60)).to_i
      "#{hours}h ago"
    else
      # Days
      days = (diff / (24 * 60 * 60)).to_i
      "#{days}d ago"
    end
    
    # Right-align to match date format width (16 characters)
    result.rjust(16)
  end
end

# Main entry point
if __FILE__ == $0
  browser = S3Browser.new
  browser.run
end
