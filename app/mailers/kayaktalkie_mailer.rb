class KayaktalkieMailer < ActionMailer::Base
  self.delivery_job = KayaktalkieMailDeliveryJob
  default from: 'webmaster@arenalrafting.com'
  def self.configured?
    !Rails.env.production? || %w[KAYAK_SMTP_ADDRESS KAYAK_SMTP_PASSWORD].all? { |key| ENV[key].present? }
  end
  def password_reset(account_id, token)
    account=KayaktalkieAccount.find_by(id: account_id, active: true)
    return unless account && account.reset_password_digest == Digest::SHA256.hexdigest(token) && account.reset_password_sent_at && account.reset_password_sent_at > 1.hour.ago
    url=edit_kayaktalkie_password_url(token: token, host: 'guia-roll-app.onrender.com', protocol: 'https')
    options={}
    if Rails.env.production?
      smtp_port=Integer(ENV.fetch('KAYAK_SMTP_PORT','465'))
      options={delivery_method: :smtp, delivery_method_options: {
        address: ENV.fetch('KAYAK_SMTP_ADDRESS'), port: smtp_port,
        user_name: ENV.fetch('KAYAK_SMTP_USERNAME','webmaster@arenalrafting.com'), password: ENV.fetch('KAYAK_SMTP_PASSWORD'),
        authentication: :plain, ssl: smtp_port == 465, enable_starttls_auto: smtp_port != 465, openssl_verify_mode: 'peer'
      }}
    end
    mail(to: account.email, subject: 'Restablecer tu contraseña de KayakTalkie', **options) do |format|
      format.text { render plain: "Hola #{account.name},\n\nPara elegir una contraseña nueva abre este enlace:\n#{url}\n\nCaduca en una hora y solo puede utilizarse una vez. Si no lo solicitaste, ignora este mensaje.\nKayakTalkie&GPS" }
    end
  end
end
