class AddCompensationSettlementItemDetails < ActiveRecord::Migration[8.1]
  def change
    add_column :compensation_settlement_items, :details, :jsonb,
      null: false, default: {}
  end
end
