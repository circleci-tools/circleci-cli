# frozen_string_literal: true

require 'open3'
require 'tmpdir'
require 'yaml'

RSpec.describe 'Coverage workflow' do
  it 'writes line coverage from SimpleCov to the GitHub Actions job summary' do
    workflow_path = File.expand_path('../.github/workflows/test.yml', __dir__)
    workflow = YAML.safe_load_file(workflow_path)
    steps = workflow.fetch('jobs').fetch('test').fetch('steps')
    report = steps.find { |step| step['name'] == 'Report coverage' }

    Dir.mktmpdir do |directory|
      coverage_directory = File.join(directory, 'coverage')
      Dir.mkdir(coverage_directory)
      File.write(File.join(coverage_directory, 'coverage.json'),
                 '{"total":{"lines":{"percent":99.5,"covered":199,"total":200}}}')
      summary = File.join(directory, 'job summary.md')
      output, status = Open3.capture2e({ 'GITHUB_STEP_SUMMARY' => summary }, 'bash', '-e', '-c',
                                      report.fetch('run'), chdir: directory)

      expect(status).to be_success, output
      expect(File.read(summary)).to eq("Line coverage: 99.50% (199/200 lines)\n")
    end
  end
end
