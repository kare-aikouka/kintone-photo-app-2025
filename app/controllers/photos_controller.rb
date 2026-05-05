class PhotosController < ApplicationController
  before_action :authentication

  PICTURE_FLAG_DONE = "完了"
  SUMMARY_CACHE_VERSION = "v2"
  SUMMARY_CACHE_TTL = 3.minutes
  SUMMARY_SYSTEM_FIELDS = %w[$id レコード番号].freeze

  DETAIL_SECTIONS = [
    {
      title: "☆施工前状況",
      note: "大和様案件は、施工前敷地状況項目の中で「施工前全景」写真も撮影して下さい。",
      tables: %w[
        テーブル施工前敷地状況
        テーブル施工前_前面道路
        テーブル施工前_養生状況・施工機搬入
        テーブル看板
        テーブル管理装置の確認
        テーブルKY確認
        テーブル異常箇所
        テーブル隣接構造物確認
        テーブル設計GL・仮BM確認
      ]
    },
    {
      title: "☆配置確認",
      note: "大和案件は、配置写真各項目3か所づつ撮影して下さい。",
      tables: %w[
        テーブル配置確認追い出し
        テーブル配置確認平行
        テーブル杭芯割付状況
      ]
    },
    {
      title: "☆杭材搬入",
      tables: %w[
        テーブル材料搬入
        テーブル刷り版
        テーブル杭材検寸全景
        テーブル杭材検寸断面
        テーブル杭材検寸杭下端部
        テーブル杭材検寸杭頭端部
        テーブル施工機全景
      ]
    },
    {
      title: "☆施工開始！",
      tables: %w[
        テーブル掘削長マーキング
        テーブル杭芯オーガーセット
        テーブル杭芯ずれ確認オーガー掘削時
        テーブルオーガー掘削
        テーブル最終掘削状況
        テーブル鉛直確認
        テーブル杭建て込み状況
        テーブル杭押込状況
        テーブル建て込み状況・下杭
        テーブル鉛直確認・下杭
        テーブル杭押し込み状況・下杭
        テーブル継ぎ手状況1
        テーブル建て込み状況・中杭
        テーブル継ぎ手状況2
        テーブル建て込み状況・上杭
        テーブル鉛直確認・上杭
        テーブル杭押し込み状況・上杭
        テーブル最終圧入
        テーブル打設後杭芯確認
        テーブル杭頭レベル確認
      ]
    },
    {
      title: "☆施工終了",
      note: "大和様案件の場合、施工後敷地状況の項目の中で「施工後全景」写真も撮影して下さい。",
      tables: %w[
        テーブル清掃状況
        テーブル杭天端仕上げ確認
        テーブル完了整地状況
        テーブル施工後完了
        テーブル施工後敷地状況
        テーブル施工後道路状況
        テーブルデータ確認状況
        その他
      ]
    }
  ].freeze

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
    @machine_search_values = machine_search_values(@machine_name, params[:machine_model])
    @records = @machine_name.present? ? photo_records_for(@machine_search_values) : []
    @default_records = default_records(@records)
    @incomplete_records = @default_records.select { |record| incomplete?(record) }
    @date_tabs = date_tabs
    @records_by_date = @default_records.group_by { |record| record_date(record) || Date.current }
    @completed_records = completed_records(@default_records)
    @future_records = future_records(@default_records, @date_tabs)
    @future_incomplete_count = @future_records.count { |record| incomplete?(record) }
    @selected_filter = selected_filter
    @selected_date = selected_date(@date_tabs)
    @selected_records = selected_records
    @field_keys = record_field_keys(@records)
    @field_preview = record_field_preview(@records)
  rescue StandardError => e
    Rails.logger.error("Photos kintone fetch failed: #{e.class}: #{e.message}")
    Rails.logger.error(e.backtrace.join("\n")) if e.backtrace

    @photo_error = e
    @records = []
    @default_records = []
    @incomplete_records = []
    @completed_records = []
    @future_records = []
    @future_incomplete_count = 0
    @records_by_date = {}
    @date_tabs = []
    @selected_records = []
  end

  def show
    @page_title = '施工写真詳細'
    @record = photo_record(params[:id])
    @machine_name = field_value(@record, :machine)
    @detail_sections = visible_detail_sections(@record)
    @field_keys = record_field_keys([@record])
    @field_preview = record_field_preview([@record])
  rescue StandardError => e
    Rails.logger.error("Photo detail fetch failed: #{e.class}: #{e.message}")
    Rails.logger.error(e.backtrace.join("\n")) if e.backtrace

    @photo_error = e
    @record = nil
    @detail_sections = []
  end

  private

  def photo_record(id)
    response = KintoneSync::Record.new(photos_app_id, photos_guest_space_id).find(id)
    response["record"]
  end

  def photo_records_for(machine_values)
    normalized_values = machine_values.map { |value| normalize(value) }
    fetched_photo_records(machine_values).select do |record|
      normalized_values.include?(normalize(field_value(record, :machine)))
    end
  end

  def fetched_photo_records(_machine_values)
    Rails.cache.fetch(photo_summary_cache_key, expires_in: SUMMARY_CACHE_TTL) do
      fetch_photo_summary_records
    end
  end

  def fetch_photo_summary_records
    record_client = KintoneSync::Record.new(photos_app_id, photos_guest_space_id)
    fields = summary_field_codes(record_client)
    fetch_all_photo_records(photo_summary_query, record_client: record_client, fields: fields)
  rescue StandardError => e
    Rails.logger.warn("Photo summary fetch with limited fields failed: #{e.class}: #{e.message}")
    fetch_all_photo_records(photo_summary_query)
  end

  def photo_summary_query
    # Avoid querying the kintone drop-down field with values that may not exist
    # in its option list. Fetch only the bounded summary range, then filter locally.
    <<~QUERY.squish
      施工予定日 > FROM_TODAY(-2, MONTHS) and
      施工予定日 < FROM_TODAY(6, MONTHS)
      order by レコード番号 asc
    QUERY
  end

  def fetch_all_photo_records(base_query, record_client: KintoneSync::Record.new(photos_app_id, photos_guest_space_id), fields: nil)
    records = []
    offset = 0
    limit = 500

    loop do
      response = record_client.find_list(query: "#{base_query} limit #{limit} offset #{offset}", fields: fields)
      page = Array(response["records"])
      records.concat(page)
      break if page.count < limit

      offset += limit
    end

    records
  end

  def default_records(records)
    records.sort_by { |record| [record_date(record) || Date.new(9999, 12, 31), record_id(record).to_i] }
  end

  def completed_records(records)
    records.select { |record| record_date(record).present? && record_date(record) < Date.current }
           .sort_by { |record| [record_date(record) || Date.new(1, 1, 1), record_id(record).to_i] }
           .reverse
  end

  def future_records(records, visible_dates)
    last_visible_date = visible_dates.last || Date.current
    records.select do |record|
      date = record_date(record)
      date.nil? || date > last_visible_date
    end
  end

  def date_tabs
    (0..7).map { |index| Date.current + index.days }
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
      @future_records
    when "completed"
      @completed_records
    else
      @records_by_date.fetch(@selected_date, [])
    end
  end

  def record_date(record)
    value = field_value(record, :date)
    parse_date(value)
  end
  helper_method :record_date

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

  def field_raw_value(record, field_code)
    record&.dig(field_code, "value")
  end
  helper_method :field_raw_value

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

  def detail_table_label(table_code)
    table_code.to_s.sub(/\Aテーブル/, "")
  end
  helper_method :detail_table_label

  def detail_table_rows(record, table_code)
    Array(record&.dig(table_code, "value"))
  end
  helper_method :detail_table_rows

  def detail_table_columns(rows)
    rows.flat_map { |row| row.dig("value")&.keys || [] }.uniq
  end
  helper_method :detail_table_columns

  def detail_cell(row, column)
    row.dig("value", column)
  end
  helper_method :detail_cell

  def detail_cell_value(row, column)
    cell = detail_cell(row, column)
    return "" unless cell

    cell["value"]
  end
  helper_method :detail_cell_value

  def detail_file_cell?(row, column)
    detail_cell(row, column)&.dig("type") == "FILE"
  end
  helper_method :detail_file_cell?

  def photo_status(record)
    field_value(record, :photo_status).presence || "未完了"
  end
  helper_method :photo_status

  def incomplete?(record)
    photo_status(record) != PICTURE_FLAG_DONE
  end
  helper_method :incomplete?

  def normalize(value)
    value.to_s.strip.tr("Ａ-Ｚａ-ｚ０-９", "A-Za-z0-9").gsub(/[[:space:]　]+/, "")
  end

  def machine_search_values(*values)
    values.flatten.compact_blank.flat_map do |value|
      raw = value.to_s.strip
      [
        raw,
        raw.tr("　", " "),
        raw.gsub(/[[:space:]　]+/, "")
      ]
    end.compact_blank.uniq
  end

  def machine_query_values(values)
    variants = machine_search_values(values)

    variants.map { |variant| %("#{kintone_query_value(variant)}") }.join(",")
  end

  def kintone_query_value(value)
    value.to_s.gsub(/[\\"]/) { |char| "\\#{char}" }
  end

  def visible_detail_sections(record)
    enabled = Array(record&.dig("報告書フォーマット撮影写真", "value")).map(&:to_s)

    DETAIL_SECTIONS.filter_map do |section|
      tables = section[:tables].select do |table_code|
        rows = detail_table_rows(record, table_code)
        enabled.include?(detail_table_label(table_code)) || rows.present? || table_code == "その他"
      end
      next if tables.blank?

      section.merge(tables: tables)
    end
  end

  def photo_summary_cache_key
    [
      "photos-summary",
      SUMMARY_CACHE_VERSION,
      photos_app_id,
      photos_guest_space_id
    ].join(":")
  end

  def summary_field_codes(record_client)
    available_codes = record_client.properties.keys
    (FIELD_ALIASES.values.flatten + SUMMARY_SYSTEM_FIELDS).uniq.select do |field_code|
      field_code.start_with?("$") || available_codes.include?(field_code)
    end
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
