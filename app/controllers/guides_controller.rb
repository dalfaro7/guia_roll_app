class GuidesController < ApplicationController
  def index
  @guides = Guide.includes(:skills)

  if params[:name].present?
    @guides = @guides.where("LOWER(name) LIKE ?", "%#{params[:name].downcase}%")
  end

  if params[:priority].present?
    @guides = @guides.where(priority: params[:priority])
  end

  if params[:skill_id].present?
    @guides = @guides.joins(:skills).where(skills: { id: params[:skill_id] })
  end

  @guides = @guides.order(:priority, :name)
end

  def edit
  @guide = Guide.find(params[:id])
end

  def new
    @guide = Guide.new
  end

  def update
  @guide = Guide.find(params[:id])

  if @guide.update(guide_params)
    redirect_to guides_path, notice: "Guide updated successfully."
  else
    render :edit
  end
end

  def create

  @guide = Guide.new(guide_params)

  if @guide.save
    redirect_to guides_path, notice: "Guide created successfully."
  else
    Rails.logger.info "ERRORS:"
    Rails.logger.info @guide.errors.full_messages
    render :new
  end
end

  private

  def guide_params
  params.require(:guide).permit(:name, :active, :priority, :day_off_balance, 
  :day_off_balance_updated_at,  skill_ids: [])
end
end