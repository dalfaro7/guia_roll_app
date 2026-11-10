module WorkDaysHelper
  def sara_candidate_label(candidate)
    return candidate.label unless current_user.hg_sarapiqui?

    candidate.label.sub("reserva prioridad 6", "freelance")
  end
end
