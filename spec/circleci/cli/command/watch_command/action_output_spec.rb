# frozen_string_literal: true

require 'spec_helper'

describe CircleCI::CLI::Command::ActionOutput do
  subject(:action_output) { described_class.new(url, session) }

  let(:url) { 'https://circleci.com/output' }
  let(:session) { instance_double(CircleCI::CLI::Networking::HTTPClient::Session) }
  let(:output) { +'' }
  let(:write_output) { ->(text) { output << text } }

  def expect_full_response(offset, *chunks)
    response = Net::HTTPOK.new('1.1', '200', 'OK')
    allow(response).to receive(:read_body) { |&read_chunk| chunks.each(&read_chunk) }
    expect(session).to receive(:get_raw).with(url, { 'Range' => "bytes=#{offset}-" }).ordered.and_yield(response)
  end

  it 'streams the unread suffix of full responses and finalizes without duplicating output' do
    expect_full_response(0, "prefix\n")
    expect_full_response(7, 'pre', "fix\nsuffix\n")
    expect_full_response(14, "prefix\nsuffix\n")

    expect(action_output.read(&write_output)).to eq(:complete)
    expect(action_output.read(&write_output)).to eq(:complete)
    expect(action_output.finish_output?(&write_output)).to be(true)
    expect(output).to eq("prefix\nsuffix\n")
  end

  it 'retries a full response shorter than the saved offset without moving the offset' do
    expect_full_response(0, "é\n")
    expect_full_response(3, 'é')
    expect_full_response(3, "é\nnext")

    expect(action_output.read(&write_output)).to eq(:complete)
    expect(action_output.finish_output?(&write_output)).to be(true)
    expect(output).to eq("é\nnext\n")
  end

  it 'retries on a SocketError raised while reading the response' do
    expect(session).to receive(:get_raw).with(url, { 'Range' => 'bytes=0-' }).and_raise(SocketError)

    expect(action_output.read(&write_output)).to eq(:retry)
  end
end
