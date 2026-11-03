module Compensation
  class Current < ActiveSupport::CurrentAttributes
    attribute :actor, :reason
  end
end
