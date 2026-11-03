class TransportCompaniesController < ApplicationController
  before_action :require_admin!

  def index
    @companies = TransportCompany.includes(:buses, :drivers).order(:name)
  end

  def create
    company = TransportCompany.new(company_params)
    if company.save
      redirect_to transport_companies_path, notice: "Empresa registrada."
    else
      redirect_to transport_companies_path, alert: company.errors.full_messages.to_sentence
    end
  end

  def update
    company = TransportCompany.find(params[:id])
    if company.update(company_params)
      company.buses.update_all(company: company.name)
      redirect_to transport_companies_path, notice: "Empresa actualizada."
    else
      redirect_to transport_companies_path, alert: company.errors.full_messages.to_sentence
    end
  end

  private

  def company_params
    params.require(:transport_company).permit(:name)
  end
end
