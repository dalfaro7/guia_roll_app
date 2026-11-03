# Run with `bin/rails runner script/correct_provisional_departure_times.rb` to preview.
# Pass --apply to correct only future scheduled outings left at provisional 06:00.
zone = Time.find_zone!("America/Costa_Rica")
today = Time.current.in_time_zone(zone).to_date
provisional = "06:00"
candidates = Departure.joins(:work_day)
  .where(status: "scheduled", work_days: { date: (today + 1.day).. })
  .includes(:work_day)
  .select do |departure|
    Departure::FIXED_START_TIMES.key?(departure.location) &&
      departure.starts_at.in_time_zone(zone).strftime("%H:%M") == provisional
  end

candidates.each do |departure|
  puts({ id: departure.id, date: departure.work_day.date,
    location: departure.location, before: provisional,
    after: Departure.fixed_start_for(departure.work_day.date,
      departure.location).in_time_zone(zone).strftime("%H:%M") }.inspect)
end
puts "Salidas provisionales futuras: #{candidates.size}"

if ARGV.include?("--apply") && candidates.any?
  actor = User.find_by!(role: "admin")
  Departure.transaction do
    changed_days = []
    candidates.each do |candidate|
      departure = Departure.lock.find(candidate.id)
      next unless departure.status == "scheduled" &&
        departure.work_day.date > today &&
        departure.starts_at.in_time_zone(zone).strftime("%H:%M") == provisional

      original = departure.starts_at
      corrected = Departure.fixed_start_for(departure.work_day.date,
        departure.location)
      departure.update_columns(starts_at: corrected, updated_at: Time.current)
      AuditLog.create!(user: actor, work_day: departure.work_day,
        action: "correct_provisional_departure_time", auditable_type: "Departure",
        auditable_id: departure.id,
        metadata: { source: "system_correction", before: original.iso8601,
          after: corrected.iso8601, reason: "Replace provisional 06:00 with fixed operating time" })
      changed_days << departure.work_day
    end
    changed_days.uniq.each { |day| Compensation::RepriceDay.call(day) }
    puts "Salidas corregidas: #{changed_days.size}; días recalculados: #{changed_days.uniq.size}"
  end
elsif candidates.any?
  puts "Vista previa. Para aplicar: bin/rails runner script/correct_provisional_departure_times.rb --apply"
end
