require 'test_helper'
require 'erb'
require 'yaml'
class ProductionDatabaseConfigTest < ActiveSupport::TestCase
  test 'Render production config exists without DATABASE_URL and uses the existing database' do
    previous = ENV.delete('DATABASE_URL')
    begin
      config = YAML.safe_load(ERB.new(File.read(Rails.root.join('config/database.yml'))).result, aliases: true)
      assert config.key?('production')
      primary = config.fetch('production').fetch('primary')
      assert_equal 'postgresql', primary.fetch('adapter')
      assert_equal 'guia_roll_app_production', primary.fetch('database')
      assert primary.fetch('host').present?
      assert_equal ['primary'], config.fetch('production').keys
    ensure
      ENV['DATABASE_URL'] = previous if previous
    end
  end
end
