# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)

require 'minitest/autorun'
require 'minitest/reporters'
require 'tempfile'
require 'json'

Minitest::Reporters.use! Minitest::Reporters::SpecReporter.new

require_relative '../lib/tui'
require_relative '../lib/fuzzy'
