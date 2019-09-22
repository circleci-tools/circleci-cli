# frozen_string_literal: true

require 'spec_helper'

describe CircleCI::CLI do
  it 'has a version number' do
    expect(CircleCI::CLI::VERSION).not_to be nil
  end
end
