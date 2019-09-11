# frozen_string_literal: true

require 'pronto'
require 'open3'
require 'pathname'

module Pronto
  MypyOffence = Struct.new(:path, :line, :type, :message) do
    def self.create_from_output_line(line)
      parts = line.split(':')
      new(Pathname.new(parts[0].strip), parts[1].strip.to_i, parts[2].strip, parts[3..-1].join(':'))
    end

    def pronto_level
      case type
      when 'error'
        type.to_sym
      else
        :warning
      end
    end
  end

  class Mypy < Runner
    def initialize(patches, commit = nil)
      super(patches, commit)
    end

    def run
      return [] unless python_patches

      file_args = python_patches
        .map(&:new_file_full_path)
        .join(' ')

      return [] if file_args.empty?

      stdout, stderr, = Open3.capture3("#{pylint_executable} #{file_args}")
      stderr.strip!

      puts "WARN: pronto-mypy:\n\n#{stderr}" unless stderr.empty?

      puts "OUT:"
      puts stdout

      puts "PRONTO:"
      stdout.split("\n")
        .map { |line| MypyOffence.create_from_output_line(line) }
        .map { |o| [patch_line_for_offence(o), o] }
        .reject { |(line, _)| line.nil? }
        .map { |(line, offence)| create_message(line, offence) }
    end

    private

    def pylint_executable
      'mypy'
    end

    def python_patches
      @python_patches ||= @patches
        .select { |p| p.additions.positive? }
        .select { |p| p.new_file_full_path.extname == '.py' }
    end

    def patch_line_for_offence(offence)
      python_patches
        .select { |patch| patch.new_file_full_path == offence.path.expand_path }
        .flat_map(&:added_lines)
        .find { |patch_lines| patch_lines.new_lineno == offence.line }
    end

    def create_message(patch_line, offence)
      puts "MESSAGE!!!"
      Message.new(
        offence.path.to_s,
        patch_line,
        offence.pronto_level,
        offence.message,
        nil,
        self.class
      )
    end
  end
end
