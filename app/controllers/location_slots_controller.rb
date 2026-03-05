class LocationSlotsController < ApplicationController
  
  
  def update_all

  params[:slots]&.each do |slot_id, skill_ids|

    slot = LocationSlot.find(slot_id)

    slot.skill_ids = skill_ids.reject(&:blank?)

  end

  work_day = LocationSlot.find(params[:slots].keys.first).work_day

  redirect_to work_day_path(work_day),
              notice: "Slot requirements updated."

end
  
  def update_skills
    # params esperado:
    # slot_skills => {
    #   "25" => ["3","10"],
    #   "26" => ["3"]
    # }

    slots_params = params[:slot_skills] || {}

    ActiveRecord::Base.transaction do
      slots_params.each do |slot_id, skill_ids|
        slot = LocationSlot.find(slot_id)

        # borrar requisitos actuales
        slot.slot_skills.destroy_all

        # recrear requisitos
        Array(skill_ids).each do |skill_id|
          slot.slot_skills.create!(skill_id: skill_id)
        end
      end
    end

    # redirigir al work_day correspondiente
    first_slot_id = slots_params.keys.first
    work_day = first_slot_id ? LocationSlot.find(first_slot_id).work_day : nil

    redirect_to(work_day ? work_day_path(work_day) : root_path,
                notice: "Slot skills updated.")
  end
end