class KayaktalkieReportDelivery < ApplicationRecord
  belongs_to :kayaktalkie_field_report
  belongs_to :kayaktalkie_session
end
