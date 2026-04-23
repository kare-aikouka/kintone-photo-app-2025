class PhotosController < ApplicationController
  before_action :authentication

  PICTURE_FLAG_DONE = "完了"

  FIELD_ALIASES = {
    machine: %w[施工機 施工機通称 施工班通称 施工機名 施工班名 施工班 機械名 重機名],
    date: %w[施工予定日 日付 施工日 作業日 撮影日 予定日 開始日 日時 登録日時],
    company: %w[発注会社名 会社名 取引先名 顧客名 運用会社名 施工会社 施工会社名],
    branch: %w[支店 支店名 営業所 営業所名],
    site: %w[物件名 現場名 工事名 案件名],
    detail: %w[打設明細 明細 工事内容],
    address: %w[住所 現場住所 施工場所 場所],
    prefecture: %w[都道府県],
    county: %w[郡],
    city: %w[市町村],
    address_tail: %w[その他住所 以降住所 番地],
    photo_status: %w[写真完了フラグ 写真 写真状況 写真ステータス],
    management_status: %w[管理 管理状況 管理ステータス]
  }.freeze

  def index
    @machine_name = params[:machine].to_s.strip
    @records = @machine_name.present? ? photo_records_for(@machine_name) : []
    @default_records = default_records(@records)
    @incomplete_records = @default_records.select { |record| incomplete?(record) }
    @past_incomplete_records = past_incomplete_records(@default_records)
    @records_by_date = @default_records.group_by { |record| record_date(record) || Date.current }
    @date_tabs = next_week_tabs
    @selected_filter = selected_filter
    @selected_date = selected_date(@date_tabs)
    @selected_records = selected_records
    @field_keys = record_field_keys(@records.presence || sample_photo_records)
    @field_preview = record_field_preview(@records.presence || sample_photo_records)
  rescue StandardError => e
    Rails.logger.error("Photos kintone fetch failed: #{e.class}: #{e.message}")
    Rails.logger.error(e.backtrace.join("\n")) if e.backtrace

    @photo_error = e
    @records = []
    @default_records = []
    @incomplete_records = []
    @past_incomplete_records = []
    @records_by_date = {}
    @date_tabs = []
    @selected_records = []
  end

  def show
    @page_title = '施工写真詳細'
  end

  private

  def photo_records_for(machine_name)
    fetched_photo_records(machine_name).select do |record|
      normalize(field_value(record, :machine)) == normalize(machine_name)
    end
  end

  def fetched_photo_records(machine_name)
    # Original app queried app 779 by the "施工機" field and then filtered again in JS.
    base_query = <<~QUERY.squish
      施工機 in ("#{kintone_query_value(machine_name)}") and
      施工予定日 > FROM_TODAY(-2, MONTHS) and
      施工予定日 < FROM_TODAY(1, WEEKS)
      order by レコード番号 asc
    QUERY
    fetch_all_photo_records(base_query)
  rescue StandardError => e
    Rails.logger.warn("Photos filtered query failed; falling back to all records: #{e.class}: #{e.message}")
    fetch_all_photo_records("order by レコード番号 asc")
  end

  def fetch_all_photo_records(base_query)
    record_client = KintoneSync::Record.new(photos_app_id, photos_guest_space_id)
    records = []
    offset = 0
    limit = 500

    loop do
      response = record_client.find_list(query: "#{base_query} limit #{limit} offset #{offset}")
      page = Array(response["records"])
      records.concat(page)
      break if page.count < limit

      offset += limit
    end

    records
  end

  def sample_photo_records
    @sample_photo_records ||= fetch_all_photo_records("order by レコード番号 asc").first(1)
  rescue StandardError
    []
  end

  def default_records(records)
    begin_date = Date.current.prev_month
    records.select do |record|
      date = record_date(record)
      date.nil? || date >= begin_date || incomplete?(record)
    end.sort_by { |record| [incomplete?(record) ? 0 : 1, record_date(record) || Date.new(9999, 12, 31)] }
  end

  def past_incomplete_records(records)
    records.select { |record| incomplete?(record) && record_date(record).present? && record_date(record) < Date.current }
  end

  def next_week_tabs
    (0..6).map { |index| Date.current + index.days }
  end

  def selected_date(date_tabs)
    requested = parse_date(params[:date])
    return requested if requested

    date_tabs.first || Date.current
  end

  def selected_filter
    params[:date].presence
  end

  def selected_records
    case @selected_filter
    when "all"
      @default_records
    when "incomplete"
      @incomplete_records
    else
      dated_records = @records_by_date.fetch(@selected_date, [])
      (@past_incomplete_records + dated_records).uniq
    end
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

  def record_title(record)
    [field_value(record, :company), field_value(record, :branch), field_value(record, :site), field_value(record, :detail)].compact_blank.join("　")
  end
  helper_method :record_title

  def record_address(record)
    direct_address = field_value(record, :address)
    return direct_address if direct_address.present?

    [field_value(record, :prefecture), field_value(record, :county), field_value(record, :city), field_value(record, :address_tail)].compact_blank.join
  end
  helper_method :record_address

  def record_id(record)
    record&.dig("$id", "value") || record&.dig("レコード番号", "value")
  end
  helper_method :record_id

  def photo_status(record)
    field_value(record, :photo_status).presence || "未完了"
  end
  helper_method :photo_status

  def incomplete?(record)
    photo_status(record) != PICTURE_FLAG_DONE
  end
  helper_method :incomplete?

  def normalize(value)
    value.to_s.strip.tr("Ａ-Ｚａ-ｚ０-９", "A-Za-z0-9")
  end

  def kintone_query_value(value)
    value.to_s.gsub(/[\\"]/) { |char| "\\#{char}" }
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
    (ENV["APP_PHOTOS"].presence || ENV["APP_PHOTO"].presence || 779).to_i
  end

  def photos_guest_space_id
    ENV["GUEST_SPACE"].presence&.to_i || 57
  end
end
