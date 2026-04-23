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
    @companies = @machines.map { |m| m["運用会社名"]["value"] }.uniq.compact
    @selected_area = area
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
  end

  private

  def fetch_machine_records(app_id, guest_space_id, cond)
    records = KintoneSync::Machines.new(app_id, guest_space_id).where(cond)
    records.is_a?(Hash) ? records["records"] : records
  end

  def machines_app_id
    ENV.fetch("APP_MACHINES", 898).to_i
  end

  def machines_guest_space_id
    ENV.fetch("GUEST_SPACE", 57).to_i
  end
end
