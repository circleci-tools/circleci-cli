# frozen_string_literal: true

require 'spec_helper'

describe CircleCI::CLI::Printer do
  describe '.escape_controls' do
    it 'escapes controls while preserving non-UTF-8 text and its encoding' do
      text = "caf\u00E9\e\r\n".encode(Encoding::ISO_8859_1)

      escaped = described_class.escape_controls(text, multiline: true)

      expect(escaped).to eq("caf\u00E9\\x1B\n".encode(Encoding::ISO_8859_1))
      expect(escaped.encoding).to eq(Encoding::ISO_8859_1)
    end

    it 'escapes bidirectional controls in binary input decoded as UTF-8' do
      text = "caf\u00E9\u061C\u202E\r\n\xFF".b

      expect(described_class.escape_controls(text, multiline: true)).to eq("caf\u00E9\\x61C\\x202E\n\\xFF")
    end
  end
end
