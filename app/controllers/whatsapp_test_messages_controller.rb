class WhatsappTestMessagesController < ApplicationController
  before_action :require_admin!

  def new
    set_defaults
  end

  def create
    set_form_values

    result = Whatsapp::Client.new.send_template(
      to: @to,
      template_name: @template_name,
      language_code: @language_code
    )

    if result.success?
      redirect_to new_whatsapp_test_message_path,
                  notice: "Mensaje de prueba enviado a Meta correctamente."
    else
      render_meta_error(result)
    end
  rescue Whatsapp::Client::ConfigurationError, ArgumentError => e
    render_local_error(e.message)
  rescue StandardError => e
    render_connection_error(e)
  end

  def check
    set_defaults
    result = Whatsapp::Client.new.phone_numbers

    if result.success?
      @phone_numbers = result.body.fetch("data", [])
      flash.now[:notice] = "Conexión con la cuenta de WhatsApp verificada."
      render :new
    else
      render_meta_error(result)
    end
  rescue Whatsapp::Client::ConfigurationError, ArgumentError => e
    render_local_error(e.message)
  rescue StandardError => e
    render_connection_error(e)
  end

  private

  def set_defaults
    @to = ""
    @template_name = "hello_world"
    @language_code = "en_US"
  end

  def set_form_values
    permitted = params.require(:whatsapp_test_message).permit(
      :to,
      :template_name,
      :language_code
    )
    @to = permitted[:to].to_s
    @template_name = permitted[:template_name].to_s
    @language_code = permitted[:language_code].to_s
  end

  def render_meta_error(result)
    error_message = result.body.dig("error", "message") || "Meta rechazó la solicitud."
    flash.now[:alert] = "Error de Meta (HTTP #{result.status}): #{error_message}"
    render :new, status: :unprocessable_entity
  end

  def render_local_error(message)
    flash.now[:alert] = message
    render :new, status: :unprocessable_entity
  end

  def render_connection_error(error)
    Rails.logger.error("[WHATSAPP TEST] #{error.class}: #{error.message}")
    flash.now[:alert] = "No se pudo conectar con WhatsApp. Revise los registros de Render."
    render :new, status: :service_unavailable
  end
end
