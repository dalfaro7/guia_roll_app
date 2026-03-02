class GuidesController < ApplicationController
  def index
    @guides = Guide.order(:name)
  end

  def new
    @guide = Guide.new
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
  params.require(:guide).permit(:name, :active, :priority)
end
end