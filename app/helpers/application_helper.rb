module ApplicationHelper
  def office_employee_day_entry(day, &block)
    content = capture(&block)
    return content unless current_user&.admin?

    link_to(
      content,
      edit_office_employee_day_path(day),
      class: "text-decoration-none"
    )
  end
end
