class WorkDaysController < ApplicationController
  before_action :set_work_day, only: [
    :show,
    :update,
    :generate_roles,
    :publish,
    :unpublish,
    :reset_roll
  ]

  def index
    @work_days = WorkDay.order(date: :asc)
  end

  def show
    @guide_days = @work_day.guide_days.includes(:guide)
  end

  def new
    @work_day = WorkDay.new
  end

  def create
    @work_day = WorkDay.new(work_day_params)

    if @work_day.save
      redirect_to @work_day, notice: "Work day created."
    else
      render :new
    end
  end

  # =====================================
  # UPDATE
  # =====================================
  def update
    new_count = work_day_params[:guides_requested].to_i

    if new_count != @work_day.guides_requested
      @work_day.regenerate_with_new_count!(new_count)
      redirect_to @work_day, notice: "Work day regenerated."
      return
    end

    if @work_day.update(work_day_params)
      redirect_to @work_day, notice: "Work day updated."
    else
      render :edit
    end
  end

  # =====================================
  # GENERATE ROLES
  # =====================================
  def generate_roles
  guides = guides_sorted_by_equity
  assigned_count = 0

  guides.each do |guide|

    guide_day = GuideDay.find_or_initialize_by(
      guide: guide,
      work_day: @work_day
    )

    # Si está libre o vacaciones → respetar
    if guide_day.day_off? || guide_day.vacation?
      next
    end

    status =
      if assigned_count < @work_day.guides_requested
        assigned_count += 1
        :worked
      else
        :standby
      end

    guide_day.update!(
      status: status,
      role_primary: assign_primary_role(status),
      manually_modified: false
    )
  end
end

  # =====================================
  # PUBLISH
  # =====================================
  def publish
    unless @work_day.generated?
      redirect_to @work_day, alert: "Only generated days can be published."
      return
    end

    worked_count = @work_day.guide_days.worked.count

    if worked_count != @work_day.guides_requested
      redirect_to @work_day, alert: "Assignments incomplete."
      return
    end

    @work_day.publish!
    redirect_to @work_day, notice: "Work day published."
  end

  # =====================================
  # UNPUBLISH
  # =====================================
  def unpublish
    if @work_day.published?
      @work_day.unpublish!
      redirect_to @work_day, notice: "Work day unpublished."
    else
      redirect_to @work_day, alert: "Only published days can be unpublished."
    end
  end

   # =====================================
  # RESET ROLL
  # =====================================
  def reset_roll
  @work_day.reset_roll!
  redirect_to @work_day, notice: "Roll reset. You may now set new availability."
  end

  private

  def set_work_day
    @work_day = WorkDay.find(params[:id])
  end

  def work_day_params
    params.require(:work_day).permit(:date, :guides_requested)
  end

end