class PhotosController < ApplicationController
  before_action :authentication

  FIELD_ALIASES = {
    machine: %w[施工機通称 施工班通称 施工機名 施工機 施工班名 施工班 機械名 重機名],
    date: %w[日付 施工日 作業日 撮影日 予定日 開始日 日時 登録日時],
    time: %w[時刻 時間 開始時刻 開始時間],
    company: %w[会社名 取引先名 顧客名 運用会社名 施工会社 施工会社名],
    branch: %w[支店 営業所 支店名 営業所名],
    site: %w[現場名 物件名 工事名 案件名],
    address: %w[住所 現場住所 施工場所 場所],
    photo_status: %w[写真 写真状況 写真ステータス],
    management_status: %w[管理 管理状況 管理ステータス]
  }.freeze

  def index
    @machine_name = params[:machine].to_s
    @records = @machine_name.present? ? photo_records_for(@machine_name) : []
    @records_by_date = @records.group_by { |record| record_date(record) || Date.current }
    @date_tabs = date_tabs(@records_by_date)
    @selected_date = selected_date(@date_tabs)
    @selected_records = @records_by_date.fetch(@selected_date, [])
    @field_keys = record_field_keys(@records.presence || all_photo_records.first(1))
    @field_preview = record_field_preview(@records.presence || all_photo_records.first(1))
  rescue StandardError => e
    Rails.logger.error("Photos kintone fetch failed: #{e.class}: #{e.message}")
    Rails.logger.error(e.backtrace.join("\n")) if e.backtrace

    @photo_error = e
    @records = []
    @records_by_date = {}
    @date_tabs = []
    @selected_records = []
  end

  def show
    @page_title = '施工写真詳細'
  end

  private

  def photo_records_for(machine_name)
    all_photo_records.select do |record|
      normalize(field_value(record, :machine)) == normalize(machine_name)
    end
  end

  def all_photo_records
    @all_photo_records ||= begin
      records = KintoneSync::Record.new(photos_app_id, photos_guest_space_id).where({})
      Array(records.is_a?(Hash) ? records["records"] : records)
    end
  end

  def date_tabs(records_by_date)
    dates = records_by_date.keys.compact.sort
    return [] if dates.empty?

    today = Date.current
    range = (today..[today + 6, dates.max].max).to_a
    (range + dates).uniq.sort
  end

  def selected_date(date_tabs)
    requested = parse_date(params[:date])
    return requested if requested && date_tabs.include?(requested)

    date_tabs.first || Date.current
  end

  def record_date(record)
    value = field_value(record, :date)
    parse_date(value)
  end

  def parse_date(value)
    return value if value.is_a?(Date)
    return if value.blank?

    Date.parse(value.to_s)
  rescue ArgumentError
    nil
  end

  def field_value(record, key)
    FIELD_ALIASES.fetch(key).each do |field_code|
      value = record&.dig(field_code, "value")
      return value if value.present?
    end
    nil
  end
  helper_method :field_value

  def normalize(value)
    value.to_s.strip.tr("Ａ-Ｚａ-ｚ０-９", "A-Za-z0-9")
  end

  def record_field_keys(records)
    sample = Array(records).find(&:present?)
    sample.respond_to?(:keys) ? sample.keys : []
  end

  def record_field_preview(records)
    sample = Array(records).find(&:present?)
    return {} unless sample.respond_to?(:each)

    sample.each_with_object({}) do |(key, field), result|
      result[key] = field.is_a?(Hash) ? field["value"] : field
    end
  end

  def photos_app_id
    ENV.fetch("APP_PHOTOS", 779).to_i
  end

  def photos_guest_space_id
    ENV["GUEST_SPACE"].presence&.to_i || 57
  end
end
