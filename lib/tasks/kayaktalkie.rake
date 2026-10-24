namespace :kayaktalkie do
  desc 'Create the first independent admin using KAYAK_NAME, KAYAK_PHONE, KAYAK_PASSWORD'
  task bootstrap_admin: :environment do
    abort 'An admin already exists; use account management.' if KayaktalkieAccount.where(role: 'admin').exists?
    account=KayaktalkieAccount.create!(name: ENV.fetch('KAYAK_NAME'), phone: ENV.fetch('KAYAK_PHONE'), password: ENV.fetch('KAYAK_PASSWORD'), role: 'admin', location_enabled: false)
    puts "Independent admin created: account ##{account.id}"
  end
end
