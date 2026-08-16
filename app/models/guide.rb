class Guide < ApplicationRecord
  has_many :guide_skills, dependent: :destroy
  has_many :skills, through: :guide_skills

  has_many :guide_days, dependent: :destroy
  has_many :monthly_balances, dependent: :destroy
  has_many :manual_day_offs, dependent: :destroy

  validates :name, presence: true
  validates :priority, presence: true

  scope :active, -> { where(active: true) }

  # Si cambia la prioridad, los rolls futuros generados
  # deben recalcularse porque la posición del guía puede cambiar.
  after_update :reset_future_generated_days,
               if: :saved_change_to_priority?

  # Al activar un guía se inicia un nuevo ciclo de fairness.
  #
  # Esto NO ocurre al editar nombre, prioridad, skills u otros campos.
  before_update :reset_fairness_when_activated

  # Si por alguna razón se crea un guía ya activo,
  # se inicializa también su ciclo de fairness.
  before_create :set_initial_fairness_started_on

  before_save :update_day_off_balance_timestamp

  def consume_day_off!
    self.day_off_balance ||= 0
    self.day_off_balance -= 1

    save!
  end

  private

  # Un cambio de prioridad puede alterar el resultado de rolls
  # futuros que ya fueron generados, por lo que se reinician.
  def reset_future_generated_days
    future_days =
      WorkDay
        .where("date >= ?", Date.current)
        .generated

    future_days.find_each do |day|
      RoleResetService.new(day).call
    end
  end

  # Reinicia el ciclo únicamente cuando ocurre:
  #
  # inactive -> active
  #
  # Desactivar al guía NO borra ni modifica la fecha anterior.
  # Cuando vuelva a activarse se establecerá una nueva fecha.
  def reset_fairness_when_activated
    return unless will_save_change_to_active?
    return unless active?

    self.fairness_started_on = Date.current
  end

  # Protege el caso en que un Guide sea creado directamente
  # como activo desde consola, seed o algún flujo antiguo.
  def set_initial_fairness_started_on
    return unless active?

    self.fairness_started_on ||= Date.current
  end

  def update_day_off_balance_timestamp
    return unless will_save_change_to_day_off_balance?

    self.day_off_balance_updated_at = Time.current
  end
end