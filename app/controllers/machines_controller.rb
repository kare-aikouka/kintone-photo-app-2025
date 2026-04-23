class MachinesController < ApplicationController
  before_action :authentication

  def index
    guest_space_id = machines_guest_space_id
    app_id = machines_app_id
    area = params[:area] || "北海道"

    if area == "本州"
      areas = %w[東北 関東 中部 近畿 中国 四国]
      records = areas.flat_map do |a|
        fetch_machine_records(app_id, guest_space_id, { "エリア" => a })
      end
      @machines = records.flatten(1)
    else
      @machines = fetch_machine_records(app_id, guest_space_id, { "エリア" => "北海道" })
    end
    log_machine_field_keys(@machines)
    @machine_field_keys = machine_field_keys(@machines)
    @machine_field_preview = machine_field_preview(@machines)
    @companies = @machines.filter_map { |machine| field_value(machine, "運用会社名") }.uniq
    @selected_area = area
  rescue StandardError => e
    render_kintone_error(e, app_id: app_id, guest_space_id: guest_space_id)
  end

  def show
    guest_space_id = machines_guest_space_id
    app_id = machines_app_id
    area = params[:area] || "北海道"
    company = params[:id]

    cond = { "エリア" => area, "運用会社名" => company }
    @machines = fetch_machine_records(app_id, guest_space_id, cond)
    @company = company
    @selected_area = area
  rescue StandardError => e
    render_kintone_error(e, app_id: app_id, guest_space_id: guest_space_id)
  end

  private

  def field_value(record, field_code)
    record&.dig(field_code, "value")
  end

  def log_machine_field_keys(records)
    keys = machine_field_keys(records)
    Rails.logger.info("Machine record field keys: #{keys.join(', ')}") if keys.any?
  end

  def machine_field_keys(records)
    sample = Array(records).find(&:present?)
    sample.respond_to?(:keys) ? sample.keys : []
  end

  def machine_field_preview(records)
    sample = Array(records).find(&:present?)
    return {} unless sample.respond_to?(:each)

    sample.each_with_object({}) do |(key, field), result|
      result[key] = field.is_a?(Hash) ? field["value"] : field
    end
  end

  def fetch_machine_records(app_id, guest_space_id, cond)
    records = KintoneSync::Machines.new(app_id, guest_space_id).where(cond)
    Array(records.is_a?(Hash) ? records["records"] : records)
  end

  def machines_app_id
    ENV.fetch("APP_MACHINES", 898).to_i
  end

  def machines_guest_space_id
    ENV["GUEST_SPACE"].presence&.to_i || 57
  end

  def render_kintone_error(error, app_id:, guest_space_id:)
    Rails.logger.error("Machines kintone fetch failed: #{error.class}: #{error.message}")
    Rails.logger.error(error.backtrace.join("\n")) if error.backtrace

    @kintone_error = error
    @kintone_diagnostics = {
      app_id: app_id,
      guest_space_id: guest_space_id,
      host_configured: ENV["KINTONE_HOST"].present?,
      api_token_configured: ENV["KINTONE_API_TOKEN"].present? || ENV["KINTONE_API_TOKEN_#{app_id}"].present?,
      user_password_configured: ENV["KINTONE_USER"].present? && ENV["KINTONE_PASS"].present?,
      container_fields: ENV.fetch("KINTONE_CONTAINER_FIELDS", "エリア")
    }
    render :kintone_error, status: :bad_gateway
  end
end
