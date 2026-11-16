class OfficeDayOffBlocksController < ApplicationController
  before_action :require_office_access!
  before_action :require_admin!, except: :index

  def index
    @block = OfficeDayOffBlock.new(date: params[:date])
    load_blocks
  end

  def create
    @block = OfficeDayOffBlock.new(block_params)
    @block.created_by = current_user
    if @block.save
      redirect_to office_day_off_blocks_path(month: @block.date.strftime("%Y-%m")),
        notice: "Fecha bloqueada para la generación de libres de todos los oficinistas."
    else
      load_blocks
      render :index, status: :unprocessable_entity
    end
  rescue ActiveRecord::RecordNotUnique
    @block.errors.add(:date, "ya está bloqueada")
    load_blocks
    render :index, status: :unprocessable_entity
  end

  def destroy
    block = OfficeDayOffBlock.find(params[:id])
    month = block.date.strftime("%Y-%m")
    block.destroy!
    redirect_to office_day_off_blocks_path(month: month),
      notice: "Bloqueo retirado. Los días libres existentes no se modificaron."
  end

  private

  def block_params
    params.require(:office_day_off_block).permit(:date, :reason)
  end

  def load_blocks
    @month = Date.strptime(params[:month].presence || Date.current.strftime("%Y-%m"), "%Y-%m").beginning_of_month
    @blocks = OfficeDayOffBlock.includes(:created_by)
      .where(date: @month.beginning_of_week(:monday)..@month.end_of_month.end_of_week(:monday)).order(:date)
  rescue ArgumentError
    @month = Date.current.beginning_of_month
    @blocks = OfficeDayOffBlock.includes(:created_by)
      .where(date: @month.beginning_of_week(:monday)..@month.end_of_month.end_of_week(:monday)).order(:date)
  end
end
