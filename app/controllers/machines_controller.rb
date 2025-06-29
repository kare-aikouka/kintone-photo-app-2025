class MachinesController < ApplicationController
  before_action :authentication

  def index
  guest_space_id = 57
  app_id = 898
  area = params[:area] || "北海道"

  if area == "本州"
    areas = %w[東北 関東 中部 近畿 中国 四国]
    records = areas.flat_map do |a|
      KintoneSync::Machines.new(app_id, guest_space_id).where({ "エリア" => a })["records"]
    end
    @machines = records.flatten(1) # これを追加
  else
    cond = { "エリア" => "北海道" }
    records = KintoneSync::Machines.new(app_id, guest_space_id).where(cond)
    @machines = records.is_a?(Hash) ? records["records"] : records
  end
  @companies = @machines.map { |m| m["運用会社名"]["value"] }.uniq.compact
  @selected_area = area
end
  def show
    guest_space_id = 57
    app_id = 898
    area = params[:area] || "北海道"
    company = params[:id]

    cond = { "エリア" => area, "運用会社名" => company }
    records = KintoneSync::Machines.new(app_id, guest_space_id).where(cond)
    @machines = records.is_a?(Hash) ? records["records"] : records
    @company = company
    @selected_area = area
  end
end
