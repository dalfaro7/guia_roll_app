ENV["RAILS_ENV"] ||= "test"

require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    parallelize(workers: :number_of_processors)
    setup do
      VoiceChannel.find_or_create_by!(room_key: 'guide-team-general') { |c| c.name = 'Arenal Rafting Team' }
      VoiceChannel.find_or_create_by!(room_key: 'abccanyoning-team') { |c| c.name = 'Abccanyoning Team' }
    end
  end
end

class ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
end
