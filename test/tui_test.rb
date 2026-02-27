# frozen_string_literal: true

require_relative 'test_helper'

class TestHelperClass
  include Tui::Helpers
end

class TuiTest < Minitest::Test
  def test_colors_enabled_by_default
    assert Tui.colors_enabled?
  end

  def test_disable_and_enable_colors
    original = Tui.colors_enabled?
    Tui.disable_colors!
    refute Tui.colors_enabled?
    Tui.enable_colors!
    assert Tui.colors_enabled?
  ensure
    Tui.colors_enabled = original
  end

  def test_ansi_constants
    assert_equal "\e[K", Tui::ANSI::CLEAR_EOL
    assert_equal "\e[2J", Tui::ANSI::CLEAR_SCREEN
    assert_equal "\e[H", Tui::ANSI::HOME
    assert_equal "\e[0m", Tui::ANSI::RESET
  end

  def test_visible_width_ascii
    assert_equal 5, Tui::Metrics.visible_width("hello")
    assert_equal 0, Tui::Metrics.visible_width("")
  end

  def test_visible_width_with_ansi_codes
    text = "\e[1mhello\e[0m"
    assert_equal 5, Tui::Metrics.visible_width(text)
  end

  def test_visible_width_emoji
    text = "📁 file"
    assert_equal 7, Tui::Metrics.visible_width(text)
  end

  def test_char_width
    assert_equal 1, Tui::Metrics.char_width('a'.ord)
    assert_equal 1, Tui::Metrics.char_width(' '.ord)
    assert_equal 2, Tui::Metrics.char_width(0x1F4C1)  # 📁
    assert_equal 0, Tui::Metrics.char_width(0xFE0F)   # variation selector
  end

  def test_truncate_short_text
    text = "hello"
    assert_equal "hello", Tui::Metrics.truncate(text, 10)
  end

  def test_truncate_long_text
    text = "hello world"
    result = Tui::Metrics.truncate(text, 8)
    assert_equal 8, Tui::Metrics.visible_width(result)
    assert result.include?("…") || result.include?("...")
  end

  def test_truncate_from_start
    text = "hello world this is long"
    result = Tui::Metrics.truncate_from_start(text, 10)
    assert_equal 10, Tui::Metrics.visible_width(result)
    assert result.end_with?("long") || result.end_with?("is long")
  end

  def test_text_bold
    Tui.enable_colors!
    result = Tui::Text.bold("test")
    assert result.include?("\e[1m")
    assert result.include?("\e[22m")
    assert result.include?("test")
  end

  def test_text_dim
    Tui.enable_colors!
    result = Tui::Text.dim("test")
    assert result.include?("test")
  end

  def test_text_highlight
    Tui.enable_colors!
    result = Tui::Text.highlight("test")
    assert result.include?("test")
  end

  def test_text_without_colors
    Tui.disable_colors!
    result = Tui::Text.bold("test")
    assert_equal "test", result
    Tui.enable_colors!
  end

  def test_terminal_size_returns_array
    size = Tui::Terminal.size
    assert_kind_of Array, size
    assert_equal 2, size.length
    assert_kind_of Integer, size[0]  # rows
    assert_kind_of Integer, size[1]  # cols
    assert size[0] > 0
    assert size[1] > 0
  end

  def test_terminal_size_with_custom_io
    io = StringIO.new
    size = Tui::Terminal.size(io)
    assert_kind_of Array, size
    assert_equal 2, size.length
  end

  def test_screen_initialization
    screen = Tui::Screen.new(width: 80, height: 24)
    assert_equal 80, screen.width
    assert_equal 24, screen.height
    assert_kind_of Tui::Section, screen.header
    assert_kind_of Tui::Section, screen.body
    assert_kind_of Tui::Section, screen.footer
  end

  def test_section_add_line
    screen = Tui::Screen.new(width: 80, height: 24)
    line = screen.header.add_line { |l| l.write.write("test") }
    assert_kind_of Tui::Line, line
  end

  def test_section_divider
    screen = Tui::Screen.new(width: 80, height: 24)
    line = screen.header.divider
    assert_kind_of Tui::Line, line
  end

  def test_section_clear
    screen = Tui::Screen.new(width: 80, height: 24)
    screen.header.add_line { |l| l.write.write("test") }
    assert_equal 1, screen.header.lines.length
    screen.header.clear
    assert_empty screen.header.lines
  end

  def test_line_segment_writer
    screen = Tui::Screen.new(width: 80, height: 24)
    line = screen.body.add_line
    line.write.write("left")
    line.right.write("right")
    refute line.write.empty?
    refute line.right.empty?
  end

  def test_line_has_input
    screen = Tui::Screen.new(width: 80, height: 24)
    line = screen.body.add_line
    refute line.has_input?
    line.mark_has_input(5)
    assert line.has_input?
  end

  def test_input_field_initialization
    field = Tui::InputField.new(placeholder: "Type here", text: "hello", cursor: 2)
    assert_equal "Type here", field.placeholder
    assert_equal "hello", field.text
    assert_equal 2, field.cursor
  end

  def test_input_field_default_cursor
    field = Tui::InputField.new(placeholder: "", text: "hello", cursor: nil)
    assert_equal 5, field.cursor
  end

  def test_input_field_cursor_bounds
    field = Tui::InputField.new(placeholder: "", text: "hi", cursor: 10)
    assert_equal 2, field.cursor
    
    field2 = Tui::InputField.new(placeholder: "", text: "hi", cursor: -5)
    assert_equal 0, field2.cursor
  end

  def test_input_field_render_placeholder
    Tui.enable_colors!
    field = Tui::InputField.new(placeholder: "Type here", text: "", cursor: 0)
    result = field.to_s
    assert result.include?("Type here")
  end

  def test_input_field_render_text
    Tui.enable_colors!
    field = Tui::InputField.new(placeholder: "", text: "hello", cursor: 2)
    result = field.to_s
    assert result.include?("he")
    assert result.include?("lo")
    assert result.include?("l")
  end

  def test_helpers_module
    helper = TestHelperClass.new
    Tui.enable_colors!
    
    result = helper.bold("test")
    assert result.include?("test")
    
    result = helper.dim("test")
    assert result.include?("test")
    
    result = helper.highlight("test")
    assert result.include?("test")
    
    result = helper.accent("test")
    assert result.include?("test")
  end

  def test_segment_writer
    writer = Tui::SegmentWriter.new
    writer.write("test")
    refute writer.empty?
    result = writer.to_s(width: 80)
    assert_equal "test", result
  end

  def test_segment_writer_write_dim
    Tui.enable_colors!
    writer = Tui::SegmentWriter.new
    writer.write_dim("test")
    result = writer.to_s(width: 80)
    assert result.include?("test")
  end

  def test_segment_writer_fill
    writer = Tui::SegmentWriter.new
    fill = writer.fill("-")
    assert_kind_of Tui::SegmentWriter::FillSegment, fill
  end

  def test_emoji_segment
    emoji = Tui::SegmentWriter::EmojiSegment.new("📁")
    assert_equal "📁", emoji.to_s
    assert_equal 2, emoji.width
  end

  def test_palette_constants
    refute_nil Tui::Palette::HEADER
    refute_nil Tui::Palette::ACCENT
    refute_nil Tui::Palette::HIGHLIGHT
    refute_nil Tui::Palette::MUTED
    refute_nil Tui::Palette::MATCH
    refute_nil Tui::Palette::INPUT_HINT
    refute_nil Tui::Palette::SELECTED_BG
    refute_nil Tui::Palette::DANGER_BG
  end

  def test_ansi_fg
    result = Tui::ANSI.fg(100)
    assert_equal "\e[38;5;100m", result
  end

  def test_ansi_bg
    result = Tui::ANSI.bg(200)
    assert_equal "\e[48;5;200m", result
  end

  def test_ansi_move_col
    result = Tui::ANSI.move_col(10)
    assert_equal "\e[10G", result
  end

  def test_ansi_sgr
    result = Tui::ANSI.sgr(1, "38;5;100")
    assert_equal "\e[1;38;5;100m", result
  end

  def test_zero_width_chars
    assert Tui::Metrics.zero_width?("\uFE00")
    assert Tui::Metrics.zero_width?("\u200B")
    refute Tui::Metrics.zero_width?("a")
  end

  def test_wide_chars
    assert Tui::Metrics.wide?("📁")
    refute Tui::Metrics.wide?("a")
    refute Tui::Metrics.wide?(" ")
  end

  def test_screen_refresh_size
    screen = Tui::Screen.new(width: 80, height: 24)
    screen.refresh_size
    assert_equal 80, screen.width
    assert_equal 24, screen.height
  end

  def test_screen_clear
    screen = Tui::Screen.new(width: 80, height: 24)
    screen.header.add_line { |l| l.write.write("test") }
    screen.body.add_line { |l| l.write.write("body") }
    
    screen.clear
    
    assert_empty screen.header.lines
    assert_empty screen.body.lines
    assert_empty screen.footer.lines
  end

  def test_screen_input_raises_if_already_has_input
    screen = Tui::Screen.new(width: 80, height: 24)
    screen.input("placeholder", value: "test", cursor: 0)
    
    assert_raises(ArgumentError) do
      screen.input("another", value: "test", cursor: 0)
    end
  end

  def test_line_center_segment
    screen = Tui::Screen.new(width: 80, height: 24)
    line = screen.body.add_line
    line.center.write("centered")
    refute line.center.empty?
  end

  def test_match_result_enumerable
    entries = [{ text: "a" }, { text: "b" }]
    fuzzy = Fuzzy.new(entries)
    result = fuzzy.match("a")
    
    assert_kind_of Enumerable, result
    assert_respond_to result, :each
    assert_respond_to result, :limit
  end

  def test_fuzzy_entry_data_class
    entry = Fuzzy::Entry.new(data: { text: "test" }, text: "test", text_lower: "test", base_score: 1.0)
    assert_equal "test", entry.text
    assert_equal "test", entry.text_lower
    assert_equal 1.0, entry.base_score
  end
end
