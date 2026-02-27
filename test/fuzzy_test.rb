# frozen_string_literal: true

require_relative 'test_helper'

class FuzzyTest < Minitest::Test
  def setup
    @entries = [
      { text: "test-file", base_score: 1.0 },
      { text: "another-file", base_score: 2.0 },
      { text: "project.rb", base_score: 0.5 },
      { text: "README.md", base_score: 1.5 },
    ]
    @fuzzy = Fuzzy.new(@entries)
  end

  def test_empty_query_returns_all_entries
    results = @fuzzy.match("").to_a
    assert_equal 4, results.length
  end

  def test_exact_match_returns_highest_score
    results = @fuzzy.match("test-file").to_a
    assert results.length > 0
    entry, positions, _score = results.first
    assert_equal "test-file", entry[:text]
    assert positions.length > 0
  end

  def test_partial_match_works
    results = @fuzzy.match("file").to_a
    texts = results.map { |e, _, _| e[:text] }
    assert_includes texts, "test-file"
    assert_includes texts, "another-file"
  end

  def test_fuzzy_match_finds_close_matches
    results = @fuzzy.match("tst").to_a
    texts = results.map { |e, _, _| e[:text] }
    assert_includes texts, "test-file"
  end

  def test_case_insensitive_matching
    results = @fuzzy.match("TEST").to_a
    texts = results.map { |e, _, _| e[:text] }
    assert_includes texts, "test-file"
  end

  def test_limit_reduces_results
    results = @fuzzy.match("file").limit(2).to_a
    assert_equal 2, results.length
  end

  def test_no_match_returns_empty
    results = @fuzzy.match("xyz123").to_a
    assert_empty results
  end

  def test_returns_highlight_positions
    results = @fuzzy.match("test").to_a
    entry, positions, score = results.first
    assert_equal "test-file", entry[:text]
    assert_equal [0, 1, 2, 3], positions
  end

  def test_base_score_affects_ranking
    entries = [
      { text: "a", base_score: 10.0 },
      { text: "a", base_score: 1.0 },
    ]
    fuzzy = Fuzzy.new(entries)
    results = fuzzy.match("a").to_a
    _entry1, _positions1, score1 = results[0]
    _entry2, _positions2, score2 = results[1]
    assert score1 > score2
  end

  def test_word_boundary_bonus
    results = @fuzzy.match("r").to_a
    texts = results.map { |e, _, _| e[:text] }
    assert_includes texts, "README.md"
  end

  def test_string_keys_work
    entries = [
      { "text" => "string-key", "base_score" => 1.0 },
    ]
    fuzzy = Fuzzy.new(entries)
    results = fuzzy.match("string").to_a
    assert_equal 1, results.length
    assert_equal "string-key", results.first[0]["text"]
  end
end
