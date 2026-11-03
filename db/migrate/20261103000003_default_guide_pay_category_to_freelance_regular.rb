class DefaultGuidePayCategoryToFreelanceRegular < ActiveRecord::Migration[8.1]
  def change
    change_column_default :guides, :pay_category, from: nil, to: "freelance_regular"
  end
end
