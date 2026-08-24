class RollNotesController < ApplicationController
  before_action :set_roll_note, only: [:destroy]

  def index
    @selected_date =
      if params[:date].present?
        Date.parse(params[:date])
      else
        Date.current
      end

    @work_day = WorkDay.find_by(
      date: @selected_date,
      status: :published
    )

    @guide_days =
      if @work_day
        @work_day.guide_days
                 .includes(:guide)
                 .where(status: [:worked, :assigned_task])
                 .order("guides.name")
      else
        GuideDay.none
      end

    @roll_notes =
      RollNote
        .includes(
          :created_by,
          work_day: [],
          guide_days: :guide
        )
        .joins(:work_day)
        .where(work_days: { date: @selected_date })
        .order(created_at: :desc)
  rescue Date::Error
    redirect_to roll_notes_path,
                alert: "Invalid date."
  end

  def create
    @work_day = WorkDay.find(params[:work_day_id])

    unless @work_day.published?
      redirect_to roll_notes_path(date: @work_day.date),
                  alert: "Notes can only be added to published rolls."
      return
    end

    @roll_note = @work_day.roll_notes.new(
      roll_note_params
    )

    @roll_note.created_by = current_user

    guide_day_ids =
      Array(params[:guide_day_ids])
        .reject(&:blank?)

    valid_guide_days =
      @work_day.guide_days
               .where(id: guide_day_ids)
               .where(status: [:worked, :assigned_task])

    ActiveRecord::Base.transaction do
      @roll_note.save!

      valid_guide_days.each do |guide_day|
        @roll_note.roll_note_guide_days.create!(
          guide_day: guide_day
        )
      end
    end

    redirect_to roll_notes_path(date: @work_day.date),
                notice: "Roll note added successfully."

  rescue ActiveRecord::RecordInvalid => e
    redirect_to roll_notes_path(date: @work_day.date),
                alert: e.record.errors.full_messages.to_sentence
  end

  def destroy
    work_day = @roll_note.work_day
    @roll_note.destroy!

    redirect_to roll_notes_path(date: work_day.date),
                notice: "Roll note deleted successfully."
  end

  private

  def set_roll_note
    @roll_note = RollNote.find(params[:id])
  end

  def roll_note_params
    params.require(:roll_note).permit(
      :note_type,
      :note
    )
  end
end