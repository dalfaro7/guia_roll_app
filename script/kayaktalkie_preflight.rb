# Read-only checks. Run after taking and verifying a production backup.
raise 'Expected production environment' unless Rails.env.production?
connection = ActiveRecord::Base.connection
expected = ENV.fetch('EXPECTED_DATABASE_NAME', 'guia_roll_app_production')
raise 'Unexpected database: aborting' unless connection.select_value('SELECT current_database()') == expected
required = %w[LIVEKIT_URL LIVEKIT_API_KEY LIVEKIT_API_SECRET]
raise 'Missing LiveKit configuration' unless required.all? { |key| ENV[key].present? }
uri = URI.parse(ENV.fetch('LIVEKIT_URL'))
raise 'LiveKit requires public WSS' unless uri.scheme == 'wss' && uri.host.present? && uri.userinfo.nil?
phone_migration_done = connection.select_value("SELECT 1 FROM schema_migrations WHERE version = '20261023193000'")
if !phone_migration_done && connection.table_exists?(:mobile_accounts) && connection.select_value('SELECT COUNT(*) FROM mobile_accounts').to_i > 0
  raise 'Existing mobile accounts require explicit phone mapping before migration'
end
puts 'KAYAKTALKIE_PREFLIGHT_OK (read-only; no migrations run)'
